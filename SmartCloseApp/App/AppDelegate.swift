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
        let isFirstRun = !appModel.settingsStore.settings.firstRunCompleted
        Log.app.info("App did finish launching. firstRun=\(isFirstRun)")
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

        if isFirstRun {
            DispatchQueue.main.async { [weak self] in
                Log.app.info("Opening onboarding window (first run)")
                self?.openOnboarding()
            }
        } else if !appModel.settingsStore.settings.showMenuBarIcon {
            // The menubar icon is normally the only way to reach Settings in this accessory app.
            // When a user hides it, launching the app again provides a recovery path rather than
            // leaving the running app with no visible UI. Keep onboarding above this path so
            // first-run users still complete setup first.
            DispatchQueue.main.async { [weak self] in
                Log.app.info("Opening settings window because the menu-bar icon is hidden")
                self?.openSettings()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !appModel.settingsStore.settings.showMenuBarIcon else {
            return false
        }

        Log.app.info("Opening settings window after app reopen because the menu-bar icon is hidden")
        openSettings()
        return false
    }

    private func openSettings() {
        Log.app.info("Opening settings window")
        let view = SettingsView()
            .environmentObject(appModel.settingsStore)
            .environmentObject(appModel.permissionManager)
            .environmentObject(appModel.inputMonitoringManager)
            .environmentObject(updaterBridge)
        if settingsWindowController == nil {
            settingsWindowController = HostingWindowController(title: "SmartClose Settings", rootView: AnyView(view))
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openDiagnostics() {
        Log.app.info("Opening diagnostics window")
        let view = DiagnosticsView()
            .environmentObject(appModel.diagnosticsStore)
        if diagnosticsWindowController == nil {
            diagnosticsWindowController = HostingWindowController(title: "SmartClose Diagnostics", rootView: AnyView(view))
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
            onboardingWindowController = HostingWindowController(title: "Welcome to SmartClose", rootView: AnyView(view), size: NSSize(width: 560, height: 420))
        }
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
