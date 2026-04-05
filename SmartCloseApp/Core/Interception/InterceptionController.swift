import AppKit
import ApplicationServices
import Foundation

final class InterceptionController {
    private let settingsStore: SettingsStore
    private let eventMonitor: EventMonitor
    private let axInspector: AXInspecting
    private let windowCountingService: WindowCountingService
    private let decisionEngine: DecisionEngine
    private let policyResolver: AppPolicyResolver
    private let actionExecutor: ActionExecutor
    private let diagnosticsStore: DiagnosticsStore

    init(
        settingsStore: SettingsStore,
        eventMonitor: EventMonitor,
        axInspector: AXInspecting,
        windowCountingService: WindowCountingService,
        decisionEngine: DecisionEngine,
        policyResolver: AppPolicyResolver,
        actionExecutor: ActionExecutor,
        diagnosticsStore: DiagnosticsStore
    ) {
        self.settingsStore = settingsStore
        self.eventMonitor = eventMonitor
        self.axInspector = axInspector
        self.windowCountingService = windowCountingService
        self.decisionEngine = decisionEngine
        self.policyResolver = policyResolver
        self.actionExecutor = actionExecutor
        self.diagnosticsStore = diagnosticsStore
    }

    @discardableResult
    func start() -> Result<Void, EventMonitorError> {
        eventMonitor.start { [weak self] event in
            self?.handle(event: event) ?? .passThrough
        }
    }

    func stop() {
        eventMonitor.stop()
    }

    private func handle(event: CGEvent) -> EventDisposition {
        let settings = settingsStore.settings
        let logVerbose = settings.debugLoggingLevel == .verbose
        let logInfo = settings.debugLoggingLevel == .info || settings.debugLoggingLevel == .verbose

        if logVerbose {
            Log.interception.debug("Handle event at location x=\(event.location.x) y=\(event.location.y)")
        }

        guard settings.isEnabled else {
            if logInfo { Log.interception.info("Pass-through: disabled") }
            return .passThrough
        }
        if settings.isPaused {
            if logInfo { Log.interception.info("Pass-through: paused") }
            return .passThrough
        }

        let point = event.location
        guard let element = axInspector.elementAtScreenPoint(point) else {
            if logVerbose { Log.interception.debug("Pass-through: no AX element at point") }
            return .passThrough
        }
        guard isCloseButton(element: element) else {
            if logVerbose { Log.interception.debug("Pass-through: element is not close button") }
            return .passThrough
        }
        guard let window = axInspector.windowForElement(element) else {
            if logVerbose { Log.interception.debug("Pass-through: no window for element") }
            return .passThrough
        }
        guard let pid = axInspector.pid(of: window) ?? axInspector.pid(of: element) else {
            if logInfo { Log.interception.info("Pass-through: no pid for window/element") }
            return .passThrough
        }
        guard let runningApp = NSRunningApplication(processIdentifier: pid) else {
            if logInfo { Log.interception.info("Pass-through: no running app for pid \(pid)") }
            return .passThrough
        }
        guard let bundleID = runningApp.bundleIdentifier else {
            if logInfo { Log.interception.info("Pass-through: missing bundle id for pid \(pid)") }
            return .passThrough
        }

        let resolved = policyResolver.resolve(bundleID: bundleID, settings: settings)
        if resolved.isExcluded {
            if logInfo { Log.interception.info("Pass-through: excluded by policy (\(resolved.matchedRule ?? "none")) bundle=\(bundleID)") }
            logDecision(
                app: runningApp,
                bundleID: bundleID,
                decision: DecisionResult(action: .passThrough, reason: "Excluded by policy"),
                windowCount: nil,
                ignoredCount: nil,
                actionTaken: "None"
            )
            return .passThrough
        }

        let appHidden = runningApp.isHidden
        let windowCountResult = windowCountingService.countWindows(for: pid, appIsHidden: appHidden, settings: settings)
        if logVerbose {
            if let windowCountResult {
                Log.interception.debug(
                    "Window count=\(windowCountResult.count) ignored=\(windowCountResult.ignoredCount) ambiguous=\(windowCountResult.ambiguous) reasons=\(windowCountResult.reasons.joined(separator: "; "), privacy: .public)"
                )
            } else {
                Log.interception.debug("Window count result: nil")
            }
        }

        let context = DecisionContext(
            isEnabled: settings.isEnabled,
            isPaused: settings.isPaused,
            permissionGranted: true,
            resolvedPolicy: resolved,
            windowCount: windowCountResult
        )

        let decision = decisionEngine.decide(context: context)
        if logInfo {
            Log.interception.info("Decision action=\(decision.action.rawValue) reason=\(decision.reason) bundle=\(bundleID)")
        }

        if decision.action == .requestQuit {
            let success = actionExecutor.requestQuit(pid: pid)
            logDecision(
                app: runningApp,
                bundleID: bundleID,
                decision: decision,
                windowCount: windowCountResult?.count,
                ignoredCount: windowCountResult?.ignoredCount,
                actionTaken: success ? "Requested quit" : "Quit request failed"
            )
            return .swallow
        }

        logDecision(
            app: runningApp,
            bundleID: bundleID,
            decision: decision,
            windowCount: windowCountResult?.count,
            ignoredCount: windowCountResult?.ignoredCount,
            actionTaken: "Passed through"
        )
        return .passThrough
    }

    private func isCloseButton(element: AXUIElement) -> Bool {
        guard let role = axInspector.role(of: element), role == kAXButtonRole as String else {
            return false
        }
        guard let subrole = axInspector.subrole(of: element) else { return false }
        return subrole == kAXCloseButtonSubrole as String
    }

    private func logDecision(
        app: NSRunningApplication,
        bundleID: String,
        decision: DecisionResult,
        windowCount: Int?,
        ignoredCount: Int?,
        actionTaken: String
    ) {
        guard settingsStore.settings.diagnosticsEnabled else { return }
        let event = DiagnosticEvent(
            id: UUID(),
            timestamp: Date(),
            appName: app.localizedName ?? "Unknown",
            bundleID: bundleID,
            windowCount: windowCount,
            ignoredCount: ignoredCount,
            decision: decision.action,
            reason: decision.reason,
            actionTaken: actionTaken
        )
        let store = diagnosticsStore
        Task { @MainActor in
            store.append(event: event)
        }
    }
}
