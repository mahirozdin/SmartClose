import AppKit
import ApplicationServices
import Foundation

@MainActor
final class InputMonitoringManager: ObservableObject {
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
        statusChecker: @escaping () -> Bool = CGPreflightListenEventAccess,
        promptRequester: @escaping () -> Bool = CGRequestListenEventAccess,
        settingsOpener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        now: @escaping () -> Date = Date.init,
        appIdentity: AppIdentitySnapshot = .current(),
        testState: PermissionTestingState? = PermissionTestingState.environmentValue(for: .inputMonitoring)
    ) {
        self.statusChecker = statusChecker
        self.promptRequester = promptRequester
        self.settingsOpener = settingsOpener
        self.now = now
        self.appIdentity = appIdentity
        self.testState = testState

        let pid = ProcessInfo.processInfo.processIdentifier
        Log.permissions.info(
            "InputMonitoringManager init pid=\(pid) bundle=\(self.appIdentity.bundleID) path=\(self.appIdentity.bundlePath) codeID=\(self.appIdentity.codeSigningIdentifier)"
        )
        refreshStatus()
    }

    var row: PermissionRowModel {
        PermissionRowModel(
            kind: .inputMonitoring,
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

        let granted = statusChecker()
        isGranted = granted

        if granted {
            rowStatus = recoveryMessage == nil ? .granted : .recoveryNeeded
        } else if isAwaitingPromptResolution {
            rowStatus = .requesting
        } else {
            rowStatus = .missing
        }

        let recoveryText = recoveryMessage ?? "none"
        Log.permissions.info(
            "Input monitoring refresh granted=\(granted) status=\(self.rowStatus.rawValue) requestedPrompt=\(self.hasRequestedSystemPrompt) recovery=\(recoveryText, privacy: .public)"
        )
    }

    func requestAccess() {
        recoveryMessage = nil
        hasRequestedSystemPrompt = true
        promptRequestedAt = now()
        Log.permissions.info("Input monitoring requestAccess called")

        guard testState == nil else {
            rowStatus = .requesting
            return
        }

        _ = promptRequester()
        refreshStatus()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            Log.permissions.info("Opening Input Monitoring System Settings")
            settingsOpener(url)
            return
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            Log.permissions.info("Opening Privacy & Security System Settings")
            settingsOpener(url)
        }
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
            return "SmartClose needs this before it can monitor close-button clicks."
        case .requesting:
            return "Approve SmartClose in the macOS prompt to continue."
        case .granted:
            return "SmartClose can monitor close-button clicks."
        case .recoveryNeeded:
            return recoveryMessage ?? "macOS granted access, but SmartClose needs a relaunch to restart event monitoring."
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
            recoveryMessage = "Relaunch SmartClose to rebuild the global event tap."
            isGranted = true
            rowStatus = .recoveryNeeded
        }
    }
}
