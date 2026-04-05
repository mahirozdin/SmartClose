import AppKit
import ApplicationServices
import Foundation
import Security

enum PermissionKind: String, Identifiable {
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    var reason: String {
        switch self {
        case .accessibility:
            return "Needed to inspect windows and confirm the red close button safely."
        case .inputMonitoring:
            return "Needed to receive global close-button clicks before macOS handles them."
        }
    }
}

enum PermissionRowStatus: String, Equatable {
    case unknown
    case missing
    case requesting
    case granted
    case recoveryNeeded

    var label: String {
        switch self {
        case .unknown:
            return "Checking"
        case .missing:
            return "Missing"
        case .requesting:
            return "Waiting for macOS"
        case .granted:
            return "Granted"
        case .recoveryNeeded:
            return "Needs relaunch"
        }
    }
}

enum PermissionRowAction: Equatable {
    case requestSystemPrompt
    case openSettings
    case relaunchApp
    case none

    var title: String? {
        switch self {
        case .requestSystemPrompt:
            return "Grant Access"
        case .openSettings:
            return "Open Settings"
        case .relaunchApp:
            return "Relaunch SmartClose"
        case .none:
            return nil
        }
    }
}

struct PermissionRowModel: Equatable, Identifiable {
    let kind: PermissionKind
    let status: PermissionRowStatus
    let action: PermissionRowAction
    let message: String

    var id: PermissionKind { kind }
    var title: String { kind.title }
    var reason: String { kind.reason }
}

struct AppIdentitySnapshot: Equatable {
    let bundleID: String
    let codeSigningIdentifier: String
    let bundlePath: String

    static func current(bundle: Bundle = .main) -> AppIdentitySnapshot {
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let bundlePath = bundle.bundleURL.path
        let codeSigningIdentifier = Self.resolveCodeSigningIdentifier() ?? bundleID
        return AppIdentitySnapshot(
            bundleID: bundleID,
            codeSigningIdentifier: codeSigningIdentifier,
            bundlePath: bundlePath
        )
    }

    private static func resolveCodeSigningIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return nil
        }

        return dict[kSecCodeInfoIdentifier as String] as? String
    }
}

enum PermissionTestingState: String {
    case missing
    case requesting
    case openSettings
    case granted
    case recovery

    static func environmentValue(for kind: PermissionKind) -> PermissionTestingState? {
        let environment = ProcessInfo.processInfo.environment
        let key: String
        switch kind {
        case .accessibility:
            key = "SMARTCLOSE_TEST_ACCESSIBILITY"
        case .inputMonitoring:
            key = "SMARTCLOSE_TEST_INPUT_MONITORING"
        }
        guard let rawValue = environment[key] else {
            return nil
        }
        return PermissionTestingState(rawValue: rawValue)
    }
}

@MainActor
protocol PermissionManaging: AnyObject {
    var isGranted: Bool { get }
    var rowStatus: PermissionRowStatus { get }
    func refreshStatus()
}

@MainActor
final class PermissionManager: ObservableObject, PermissionManaging {
    @Published private(set) var isGranted = false
    @Published private(set) var rowStatus: PermissionRowStatus = .unknown

    let appIdentity: AppIdentitySnapshot

    private let statusChecker: () -> Bool
    private let promptRequester: () -> Bool
    private let settingsOpener: (URL) -> Void
    private let now: () -> Date
    private let testState: PermissionTestingState?
    private let promptGracePeriod: TimeInterval = 4

    private var hasRequestedSystemPrompt = false
    private var promptRequestedAt: Date?
    private var recoveryMessage: String?

    init(
        statusChecker: @escaping () -> Bool = AXIsProcessTrusted,
        promptRequester: @escaping () -> Bool = {
            let options = [AXTrustedCheckOption.prompt: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        },
        settingsOpener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        now: @escaping () -> Date = Date.init,
        appIdentity: AppIdentitySnapshot = .current(),
        testState: PermissionTestingState? = PermissionTestingState.environmentValue(for: .accessibility)
    ) {
        self.statusChecker = statusChecker
        self.promptRequester = promptRequester
        self.settingsOpener = settingsOpener
        self.now = now
        self.appIdentity = appIdentity
        self.testState = testState

        let pid = ProcessInfo.processInfo.processIdentifier
        Log.permissions.info(
            "PermissionManager init pid=\(pid) bundle=\(self.appIdentity.bundleID) path=\(self.appIdentity.bundlePath) codeID=\(self.appIdentity.codeSigningIdentifier)"
        )
        refreshStatus()
    }

    var row: PermissionRowModel {
        PermissionRowModel(
            kind: .accessibility,
            status: rowStatus,
            action: action,
            message: message
        )
    }

    func refreshStatus() {
        if let testState {
            apply(testState: testState)
            return
        }

        let trusted = statusChecker()
        isGranted = trusted

        if trusted {
            rowStatus = recoveryMessage == nil ? .granted : .recoveryNeeded
        } else if isAwaitingPromptResolution {
            rowStatus = .requesting
        } else {
            rowStatus = .missing
        }

        let recoveryText = recoveryMessage ?? "none"
        Log.permissions.info(
            "AX refresh trusted=\(trusted) status=\(self.rowStatus.rawValue) requestedPrompt=\(self.hasRequestedSystemPrompt) recovery=\(recoveryText, privacy: .public)"
        )
    }

    func requestAccess() {
        recoveryMessage = nil
        hasRequestedSystemPrompt = true
        promptRequestedAt = now()
        Log.permissions.info("AX requestAccess called")

        guard testState == nil else {
            rowStatus = .requesting
            return
        }

        _ = promptRequester()
        refreshStatus()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        Log.permissions.info("Opening Accessibility System Settings")
        settingsOpener(url)
    }

    func setRecoveryMessage(_ message: String?) {
        recoveryMessage = message
        refreshStatus()
    }

    private var isAwaitingPromptResolution: Bool {
        guard hasRequestedSystemPrompt, let promptRequestedAt else {
            return false
        }
        return now().timeIntervalSince(promptRequestedAt) < promptGracePeriod
    }

    private var action: PermissionRowAction {
        switch rowStatus {
        case .granted:
            return .none
        case .recoveryNeeded:
            return .relaunchApp
        case .requesting:
            return .none
        case .missing, .unknown:
            return hasRequestedSystemPrompt ? .openSettings : .requestSystemPrompt
        }
    }

    private var message: String {
        switch rowStatus {
        case .unknown:
            return "Checking the current macOS permission state."
        case .missing:
            if hasRequestedSystemPrompt {
                return "If the prompt did not appear or was denied, enable SmartClose manually in System Settings."
            }
            return "SmartClose needs this before it can inspect windows."
        case .requesting:
            return "Approve SmartClose in the macOS prompt to continue."
        case .granted:
            return "SmartClose can inspect windows."
        case .recoveryNeeded:
            return recoveryMessage ?? "macOS granted access, but SmartClose needs a relaunch to start monitoring."
        }
    }

    private func apply(testState: PermissionTestingState) {
        switch testState {
        case .missing:
            hasRequestedSystemPrompt = false
            recoveryMessage = nil
            isGranted = false
            rowStatus = .missing
        case .requesting:
            hasRequestedSystemPrompt = true
            isGranted = false
            rowStatus = .requesting
        case .openSettings:
            hasRequestedSystemPrompt = true
            isGranted = false
            rowStatus = .missing
        case .granted:
            recoveryMessage = nil
            isGranted = true
            rowStatus = .granted
        case .recovery:
            recoveryMessage = "Relaunch SmartClose to reattach its event monitor."
            isGranted = true
            rowStatus = .recoveryNeeded
        }
    }
}
