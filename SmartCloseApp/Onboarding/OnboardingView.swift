import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var inputMonitoringManager: InputMonitoringManager
    @EnvironmentObject var settingsStore: SettingsStore

    let onRestart: () -> Void
    let onFinish: () -> Void

    @State private var step: OnboardingProgress.Step = .permissions

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case .permissions:
                permissionStep
            case .quickSetup:
                quickSetupStep
            case .allSet:
                allSetStep
            }
        }
        .padding(28)
        .frame(minWidth: 620, minHeight: 460)
        .onAppear {
            refreshPermissions()
            syncStepFromSettings()
        }
        .onReceive(refreshTimer) { _ in
            guard step == .permissions, !allPermissionsGranted else { return }
            refreshPermissions()
        }
        .onChange(of: allPermissionsGranted) { granted in
            if !granted, step != .permissions {
                step = .permissions
            }
        }
    }

    private var allPermissionsGranted: Bool {
        permissionManager.isGranted && inputMonitoringManager.isGranted
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SmartClose needs two permissions")
                .font(.title)
                .bold()

            Text("Grant both permissions below before SmartClose starts intercepting the red close button.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                PermissionRequirementRow(row: permissionManager.row) {
                    handlePrimaryAction(for: permissionManager.row)
                }
                PermissionRequirementRow(row: inputMonitoringManager.row) {
                    handlePrimaryAction(for: inputMonitoringManager.row)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Continue") {
                    enterQuickSetup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allPermissionsGranted)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var quickSetupStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Setup")
                .font(.title2)
                .bold()

            Text("These defaults are safe to change later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Enable SmartClose", isOn: settingsStore.binding(for: \.isEnabled))
            Toggle("Start SmartClose at login", isOn: settingsStore.binding(for: \.launchAtLogin))

            Spacer()

            HStack {
                Button("Back") {
                    step = .permissions
                }
                Spacer()
                Button("Continue") {
                    enterAllSet()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            persistQuickSetupState()
            if !settingsStore.settings.isEnabled {
                settingsStore.update { $0.isEnabled = true }
            }
        }
    }

    private var allSetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("All set")
                .font(.title2)
                .bold()

            Text("SmartClose is ready. You can manage rules, diagnostics, and permissions anytime from the menu bar.")
                .font(.body)

            Spacer()

            HStack {
                Spacer()
                Button("Finish") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            settingsStore.update {
                $0.onboardingProgress.lastStep = .allSet
                $0.onboardingProgress.requestedRelaunch = false
            }
        }
    }

    private func handlePrimaryAction(for row: PermissionRowModel) {
        switch row.kind {
        case .accessibility:
            switch row.action {
            case .requestSystemPrompt:
                Log.permissions.info("Onboarding: user tapped Grant Access (AX)")
                permissionManager.requestAccess()
            case .openSettings:
                Log.permissions.info("Onboarding: user tapped Open Settings (AX)")
                permissionManager.openSystemSettings()
            case .relaunchApp:
                requestRelaunch()
            case .none:
                break
            }
        case .inputMonitoring:
            switch row.action {
            case .requestSystemPrompt:
                Log.permissions.info("Onboarding: user tapped Grant Access (Input Monitoring)")
                inputMonitoringManager.requestAccess()
            case .openSettings:
                Log.permissions.info("Onboarding: user tapped Open Settings (Input Monitoring)")
                inputMonitoringManager.openSystemSettings()
            case .relaunchApp:
                requestRelaunch()
            case .none:
                break
            }
        }
    }

    private func refreshPermissions() {
        permissionManager.refreshStatus()
        inputMonitoringManager.refreshStatus()
    }

    private func syncStepFromSettings() {
        let resolved = OnboardingProgress.resolvedStep(
            for: settingsStore.settings,
            permissionsGranted: allPermissionsGranted
        )

        switch resolved {
        case .permissions:
            step = .permissions
        case .quickSetup:
            persistQuickSetupState()
            step = .quickSetup
        case .allSet:
            step = .allSet
        }

        if settingsStore.settings.onboardingProgress.requestedRelaunch {
            settingsStore.update { $0.onboardingProgress.requestedRelaunch = false }
        }
    }

    private func persistQuickSetupState() {
        settingsStore.update {
            $0.onboardingProgress.lastStep = .quickSetup
            $0.onboardingProgress.hasSeenQuickSetup = true
            $0.onboardingProgress.requestedRelaunch = false
        }
    }

    private func enterQuickSetup() {
        persistQuickSetupState()
        step = .quickSetup
    }

    private func enterAllSet() {
        settingsStore.update {
            $0.onboardingProgress.lastStep = .allSet
            $0.onboardingProgress.requestedRelaunch = false
        }
        step = .allSet
    }

    private func completeOnboarding() {
        settingsStore.update {
            $0.firstRunCompleted = true
            $0.onboardingProgress.lastStep = .allSet
            $0.onboardingProgress.requestedRelaunch = false
        }
        onFinish()
    }

    private func requestRelaunch() {
        settingsStore.update { $0.onboardingProgress.requestedRelaunch = true }
        onRestart()
    }
}

struct PermissionRequirementRow: View {
    let row: PermissionRowModel
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            statusView
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .font(.headline)
                    Text(row.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(row.reason)
                    .font(.subheadline)
                Text(row.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let actionTitle = row.action.title {
                if row.action == .requestSystemPrompt {
                    Button(actionTitle) {
                        onPrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(actionTitle) {
                        onPrimaryAction()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12))
        )
    }

    @ViewBuilder
    private var statusView: some View {
        switch row.status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .requesting:
            ProgressView()
                .controlSize(.small)
                .tint(.orange)
        case .recoveryNeeded:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.orange)
        case .missing:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .unknown:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}
