import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()

    private var statusMenuController: StatusMenuController?
    private var settingsWindowController: HostingWindowController?
    private var diagnosticsWindowController: HostingWindowController?
    private var onboardingWindowController: HostingWindowController?

    private var updaterController: SPUStandardUpdaterController?
    private var updaterBridge: UpdaterBridge!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchReason = AppLaunchReason(appleEvent: NSAppleEventManager.shared().currentAppleEvent)
        let isFirstRun = !appModel.settingsStore.settings.firstRunCompleted
        let presentation = AppPresentation.onLaunch(firstRunCompleted: !isFirstRun, reason: launchReason)
        Log.app.info("App did finish launching. firstRun=\(isFirstRun) reason=\(launchReason.rawValue, privacy: .public)")
        NSApp.setActivationPolicy(isFirstRun ? .regular : .accessory)

        // Sparkle auto-updates. Starts checking on launch; shows its own first-run consent prompt.
        let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.updaterController = updaterController
        updaterBridge = UpdaterBridge(updater: updaterController.updater)

        statusMenuController = StatusMenuController(
            settingsStore: appModel.settingsStore,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onShowDiagnostics: { [weak self] in self?.openDiagnostics() },
            onCheckForUpdates: { [weak self] in self?.updaterController?.checkForUpdates(nil) },
            onQuit: { NSApp.terminate(nil) }
        )

        if presentation != .none {
            DispatchQueue.main.async { [weak self] in
                self?.present(presentation)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Log.app.info("Showing main window after user reopened the app")
        present(.onUserRequest(firstRunCompleted: appModel.settingsStore.settings.firstRunCompleted))
        return false
    }

    private func present(_ presentation: AppPresentation) {
        switch presentation {
        case .none:
            break
        case .onboarding:
            openOnboarding()
        case .settings:
            openSettings()
        }
    }

    private func openSettings() {
        Log.app.info("Opening settings window")
        let view = SettingsView()
            .environmentObject(appModel.settingsStore)
            .environmentObject(appModel.permissionManager)
            .environmentObject(appModel.inputMonitoringManager)
            .environmentObject(updaterBridge)
        if settingsWindowController == nil {
            settingsWindowController = HostingWindowController(title: String(localized: "SmartClose Settings"), rootView: AnyView(view))
        }
        settingsWindowController?.window?.deminiaturize(nil)
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openDiagnostics() {
        Log.app.info("Opening diagnostics window")
        let view = DiagnosticsView()
            .environmentObject(appModel.diagnosticsStore)
        if diagnosticsWindowController == nil {
            diagnosticsWindowController = HostingWindowController(title: String(localized: "SmartClose Diagnostics"), rootView: AnyView(view))
        }
        diagnosticsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openOnboarding() {
        Log.app.info("Opening onboarding window")
        let view = OnboardingView(
            onRestart: { [weak self] in
                Log.app.info("Onboarding requested restart")
                self?.restartApp()
            },
            onFinish: { [weak self] in
                Log.app.info("Onboarding finished")
                self?.onboardingWindowController?.close()
                NSApp.setActivationPolicy(.accessory)
            })
            .environmentObject(appModel.permissionManager)
            .environmentObject(appModel.inputMonitoringManager)
            .environmentObject(appModel.settingsStore)
        if onboardingWindowController == nil {
            onboardingWindowController = HostingWindowController(title: String(localized: "Welcome to SmartClose"), rootView: AnyView(view), size: NSSize(width: 560, height: 420))
        }
        onboardingWindowController?.window?.deminiaturize(nil)
        onboardingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restartApp() {
        AppRelauncher.relaunch()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

/// Bridges Sparkle's "automatically check for updates" preference into SwiftUI so the
/// Settings window can toggle it. Sparkle persists the value itself.
@MainActor
final class UpdaterBridge: ObservableObject {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }
}
