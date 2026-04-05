import AppKit
import Combine
import Foundation

@MainActor
final class AppModel {
    let settingsStore: SettingsStore
    let diagnosticsStore: DiagnosticsStore
    let permissionManager: PermissionManager
    let inputMonitoringManager: InputMonitoringManager
    let loginItemManager: LoginItemManager
    let interceptionController: InterceptionController

    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitorState: EventMonitorRuntimeState = .idle
    private var eventMonitorMessage: String?

    init() {
        settingsStore = SettingsStore()
        diagnosticsStore = DiagnosticsStore()
        let appIdentity = AppIdentitySnapshot.current()
        permissionManager = PermissionManager(appIdentity: appIdentity)
        inputMonitoringManager = InputMonitoringManager(appIdentity: appIdentity)
        loginItemManager = LoginItemManager()

        let axInspector = AXInspector()
        let windowClassifier = WindowClassifier()
        let windowCounter = WindowCountingService(axInspector: axInspector, classifier: windowClassifier)
        let policyResolver = AppPolicyResolver()
        let decisionEngine = DecisionEngine()
        let actionExecutor = ActionExecutor()
        let eventMonitor = EventMonitor()

        interceptionController = InterceptionController(
            settingsStore: settingsStore,
            eventMonitor: eventMonitor,
            axInspector: axInspector,
            windowCountingService: windowCounter,
            decisionEngine: decisionEngine,
            policyResolver: policyResolver,
            actionExecutor: actionExecutor,
            diagnosticsStore: diagnosticsStore
        )

        let settings = settingsStore.settings
        Log.app.info("AppModel init settings enabled=\(settings.isEnabled) paused=\(settings.isPaused) debug=\(settings.debugLoggingLevel.rawValue) firstRunCompleted=\(settings.firstRunCompleted)")

        settingsStore.$settings
            .map(\.launchAtLogin)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] launchAtLogin in
                self?.loginItemManager.setEnabled(launchAtLogin)
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map(\.isEnabled)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncRuntimeState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            permissionManager.$isGranted.removeDuplicates(),
            inputMonitoringManager.$isGranted.removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.syncRuntimeState()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(permissionManager.$rowStatus, inputMonitoringManager.$rowStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.publishDiagnostics()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Log.app.info("App became active. Refreshing permission status.")
                self?.permissionManager.refreshStatus()
                self?.inputMonitoringManager.refreshStatus()
            }
            .store(in: &cancellables)

        publishDiagnostics()
        syncRuntimeState()
    }

    private var permissionsGranted: Bool {
        permissionManager.isGranted && inputMonitoringManager.isGranted
    }

    private func syncRuntimeState() {
        let isEnabled = settingsStore.settings.isEnabled

        if permissionsGranted && isEnabled {
            Log.app.info("Permissions granted and SmartClose enabled. Starting event monitor.")
            switch interceptionController.start() {
            case .success:
                permissionManager.setRecoveryMessage(nil)
                inputMonitoringManager.setRecoveryMessage(nil)
                eventMonitorState = .running
                eventMonitorMessage = nil
            case .failure(let error):
                let recoveryMessage = "macOS granted access, but SmartClose needs a relaunch to rebuild its event monitor."
                permissionManager.setRecoveryMessage(nil)
                inputMonitoringManager.setRecoveryMessage(recoveryMessage)
                eventMonitorState = .failed
                eventMonitorMessage = error.message
                interceptionController.stop()
            }
        } else {
            interceptionController.stop()
            permissionManager.setRecoveryMessage(nil)
            inputMonitoringManager.setRecoveryMessage(nil)
            if isEnabled {
                eventMonitorState = .idle
                eventMonitorMessage = permissionsGranted ? nil : "Grant both permissions to start monitoring close-button clicks."
                Log.app.info("Permissions missing. Event monitor idle.")
            } else {
                eventMonitorState = .disabled
                eventMonitorMessage = "SmartClose is disabled."
                Log.app.info("SmartClose disabled. Event monitor stopped.")
            }
        }

        publishDiagnostics()
    }

    private func publishDiagnostics() {
        diagnosticsStore.updatePermissionSnapshot(
            PermissionDiagnosticsSnapshot(
                appIdentity: permissionManager.appIdentity,
                accessibilityRow: permissionManager.row,
                inputMonitoringRow: inputMonitoringManager.row,
                eventMonitorState: eventMonitorState,
                eventMonitorMessage: eventMonitorMessage
            )
        )
    }
}
