import AppKit
import Foundation

struct DiagnosticEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let appName: String
    let bundleID: String
    let windowCount: Int?
    let ignoredCount: Int?
    let decision: DecisionAction
    let reason: String
    let actionTaken: String
}

enum EventMonitorRuntimeState: String, Equatable {
    case idle
    case disabled
    case running
    case failed

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .disabled:
            return "Disabled"
        case .running:
            return "Running"
        case .failed:
            return "Failed"
        }
    }
}

struct PermissionDiagnosticsSnapshot: Equatable {
    var appIdentity: AppIdentitySnapshot
    var accessibilityRow: PermissionRowModel
    var inputMonitoringRow: PermissionRowModel
    var eventMonitorState: EventMonitorRuntimeState
    var eventMonitorMessage: String?

    static let `default` = PermissionDiagnosticsSnapshot(
        appIdentity: .current(),
        accessibilityRow: PermissionRowModel(
            kind: .accessibility,
            status: .unknown,
            action: .requestSystemPrompt,
            message: "Checking the current macOS permission state."
        ),
        inputMonitoringRow: PermissionRowModel(
            kind: .inputMonitoring,
            status: .unknown,
            action: .requestSystemPrompt,
            message: "Checking the current macOS permission state."
        ),
        eventMonitorState: .idle,
        eventMonitorMessage: nil
    )

    var staleTCCResetCommands: [String] {
        [
            "tccutil reset Accessibility \(appIdentity.bundleID)",
            "tccutil reset ListenEvent \(appIdentity.bundleID)"
        ]
    }
}

@MainActor
final class DiagnosticsStore: ObservableObject {
    @Published private(set) var events: [DiagnosticEvent] = []
    @Published private(set) var permissionSnapshot: PermissionDiagnosticsSnapshot = .default

    private let maxEvents = 50

    func append(event: DiagnosticEvent) {
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
    }

    func latest() -> DiagnosticEvent? {
        events.first
    }

    func updatePermissionSnapshot(_ snapshot: PermissionDiagnosticsSnapshot) {
        permissionSnapshot = snapshot
    }

    func frontmostAppSummary() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return "Unknown" }
        let name = app.localizedName ?? "Unknown"
        let bundle = app.bundleIdentifier ?? "Unknown"
        return "\(name) (\(bundle))"
    }
}
