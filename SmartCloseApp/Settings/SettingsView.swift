import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var inputMonitoringManager: InputMonitoringManager

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("SmartClose Settings")
                    .font(.title2)
                    .bold()

                permissionsSection
                behaviorSection
                appRulesSection
                diagnosticsSection
                importExportSection
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 620)
        .onAppear {
            refreshPermissions()
        }
        .onReceive(refreshTimer) { _ in
            guard !permissionManager.isGranted || !inputMonitoringManager.isGranted else { return }
            refreshPermissions()
        }
    }

    private var permissionsSection: some View {
        GroupBox(label: Text("Required Access")) {
            VStack(alignment: .leading, spacing: 12) {
                PermissionRequirementRow(row: permissionManager.row) {
                    handlePrimaryAction(for: permissionManager.row)
                }

                PermissionRequirementRow(row: inputMonitoringManager.row) {
                    handlePrimaryAction(for: inputMonitoringManager.row)
                }

                Text("SmartClose only becomes active once both permissions are green and the app is enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var behaviorSection: some View {
        GroupBox(label: Text("Behavior")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable SmartClose", isOn: settingsStore.binding(for: \.isEnabled))
                Toggle("Launch at login", isOn: settingsStore.binding(for: \.launchAtLogin))
                Toggle("Show menu bar icon", isOn: settingsStore.binding(for: \.showMenuBarIcon))

                Picker("Global mode", selection: settingsStore.binding(for: \.globalMode)) {
                    ForEach(GlobalMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Ignore minimized windows", isOn: settingsStore.binding(for: \.countMinimizedWindows).map { !$0 })
                Toggle("Ignore hidden windows", isOn: settingsStore.binding(for: \.countHiddenWindows).map { !$0 })

                HStack {
                    if settingsStore.settings.isPaused {
                        Button("Resume SmartClose") {
                            settingsStore.update { $0.pauseUntil = nil }
                        }
                    } else {
                        Button("Pause for 1 hour") {
                            settingsStore.update { $0.pauseUntil = Date().addingTimeInterval(3600) }
                        }
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appRulesSection: some View {
        GroupBox(label: Text("App Rules")) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Use * as a wildcard in bundle IDs (case-sensitive).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Toggle("Use allow list (only apply to listed apps)", isOn: settingsStore.binding(for: \.useAllowList))

                EditableStringList(
                    title: "Allow List",
                    placeholder: "com.example.app",
                    items: settingsStore.binding(for: \.allowedBundleIDs)
                )

                EditableStringList(
                    title: "Ignore List",
                    placeholder: "com.apple.finder",
                    items: settingsStore.binding(for: \.ignoredBundleIDs)
                )

                AppRulesEditorView(rules: settingsStore.binding(for: \.perAppRules))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diagnosticsSection: some View {
        GroupBox(label: Text("Diagnostics")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable diagnostics", isOn: settingsStore.binding(for: \.diagnosticsEnabled))
                Picker("Debug logging", selection: settingsStore.binding(for: \.debugLoggingLevel)) {
                    ForEach(DebugLoggingLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var importExportSection: some View {
        GroupBox(label: Text("Settings Backup")) {
            HStack {
                Button("Export Settings") {
                    settingsStore.exportToFile()
                }
                Button("Import Settings") {
                    settingsStore.importFromFile()
                }
            }
        }
    }

    private func refreshPermissions() {
        permissionManager.refreshStatus()
        inputMonitoringManager.refreshStatus()
    }

    private func handlePrimaryAction(for row: PermissionRowModel) {
        switch row.kind {
        case .accessibility:
            switch row.action {
            case .requestSystemPrompt:
                Log.permissions.info("Settings: user tapped Grant Access (AX)")
                permissionManager.requestAccess()
            case .openSettings:
                Log.permissions.info("Settings: user tapped Open Settings (AX)")
                permissionManager.openSystemSettings()
            case .relaunchApp:
                Log.permissions.info("Settings: user tapped Relaunch SmartClose (AX)")
                AppRelauncher.relaunch()
            case .none:
                break
            }
        case .inputMonitoring:
            switch row.action {
            case .requestSystemPrompt:
                Log.permissions.info("Settings: user tapped Grant Access (Input Monitoring)")
                inputMonitoringManager.requestAccess()
            case .openSettings:
                Log.permissions.info("Settings: user tapped Open Settings (Input Monitoring)")
                inputMonitoringManager.openSystemSettings()
            case .relaunchApp:
                Log.permissions.info("Settings: user tapped Relaunch SmartClose (Input Monitoring)")
                AppRelauncher.relaunch()
            case .none:
                break
            }
        }
    }
}

private extension Binding where Value == Bool {
    func map(_ transform: @escaping (Value) -> Value) -> Binding<Value> {
        Binding(
            get: { transform(wrappedValue) },
            set: { wrappedValue = transform($0) }
        )
    }
}
