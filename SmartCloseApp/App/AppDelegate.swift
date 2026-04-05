import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()

    private var statusMenuController: StatusMenuController?
    private var settingsWindowController: HostingWindowController?
    private var diagnosticsWindowController: HostingWindowController?
    private var onboardingWindowController: HostingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isFirstRun = !appModel.settingsStore.settings.firstRunCompleted
        Log.app.info("App did finish launching. firstRun=\(isFirstRun)")
        NSApp.setActivationPolicy(isFirstRun ? .regular : .accessory)

        statusMenuController = StatusMenuController(
            settingsStore: appModel.settingsStore,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onShowDiagnostics: { [weak self] in self?.openDiagnostics() },
            onQuit: { NSApp.terminate(nil) }
        )

        if isFirstRun {
            DispatchQueue.main.async { [weak self] in
                Log.app.info("Opening onboarding window (first run)")
                self?.openOnboarding()
            }
        }
    }

    private func openSettings() {
        Log.app.info("Opening settings window")
        let view = SettingsView()
            .environmentObject(appModel.settingsStore)
            .environmentObject(appModel.permissionManager)
            .environmentObject(appModel.inputMonitoringManager)
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
