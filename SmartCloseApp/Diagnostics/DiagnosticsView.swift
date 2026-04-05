import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var diagnosticsStore: DiagnosticsStore

    var body: some View {
        let snapshot = diagnosticsStore.permissionSnapshot

        return VStack(alignment: .leading, spacing: 16) {
            Text("SmartClose Diagnostics")
                .font(.title2)
                .bold()

            GroupBox(label: Text("Permission Health")) {
                VStack(alignment: .leading, spacing: 10) {
                    DiagnosticRow(label: "Bundle ID", value: snapshot.appIdentity.bundleID)
                    DiagnosticRow(label: "Code-Signing ID", value: snapshot.appIdentity.codeSigningIdentifier)
                    DiagnosticRow(label: "Bundle Path", value: snapshot.appIdentity.bundlePath)
                    DiagnosticRow(label: "Accessibility", value: snapshot.accessibilityRow.status.label)
                    DiagnosticRow(label: "Input Monitoring", value: snapshot.inputMonitoringRow.status.label)
                    DiagnosticRow(label: "Event Monitor", value: snapshot.eventMonitorState.label)

                    if let eventMonitorMessage = snapshot.eventMonitorMessage {
                        Text(eventMonitorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if snapshot.accessibilityRow.status != .granted || snapshot.inputMonitoringRow.status != .granted || snapshot.eventMonitorState == .failed {
                        Divider()
                        Text("If permissions look stale after a signing or Debug-build change, reset TCC for SmartClose and try again:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(snapshot.staleTCCResetCommands, id: \.self) { command in
                            Text(command)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Frontmost App")
                    .font(.headline)
                Text(diagnosticsStore.frontmostAppSummary())
                    .font(.subheadline)
            }

            if let latest = diagnosticsStore.latest() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Intercepted Action")
                        .font(.headline)
                    Text("App: \(latest.appName) (\(latest.bundleID))")
                    Text("Window count: \(latest.windowCount.map(String.init) ?? "-")")
                    Text("Ignored windows: \(latest.ignoredCount.map(String.init) ?? "-")")
                    Text("Decision: \(latest.decision.rawValue)")
                    Text("Reason: \(latest.reason)")
                    Text("Action taken: \(latest.actionTaken)")
                }
                .font(.subheadline)
            } else {
                Text("No recent activity yet. SmartClose only logs interception decisions after both permissions are granted and the app is enabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            List(diagnosticsStore.events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(event.appName) - \(event.decision.rawValue)")
                        .font(.headline)
                    Text(event.reason)
                        .font(.subheadline)
                    Text(event.timestamp, style: .time)
                        .font(.caption)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 560)
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.headline)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}
