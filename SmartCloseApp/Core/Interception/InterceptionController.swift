import AppKit
import ApplicationServices
import Foundation

struct CmdWVerificationPolicy: Equatable {
    let initialDelay: TimeInterval
    let retryInterval: TimeInterval
    let maxDuration: TimeInterval

    init(
        configuredInitialDelay: TimeInterval,
        retryInterval: TimeInterval = 0.2,
        maxDuration: TimeInterval = 1.0
    ) {
        initialDelay = max(0.05, configuredInitialDelay)
        self.retryInterval = max(0.05, retryInterval)
        self.maxDuration = max(initialDelay, maxDuration)
    }

    func nextDelay(afterElapsed elapsed: TimeInterval, latestResult: WindowCountResult?) -> TimeInterval? {
        guard latestResult?.count != 0 else { return nil }
        guard elapsed < maxDuration else { return nil }
        return min(retryInterval, maxDuration - elapsed)
    }
}

// All stored dependencies are immutable `let` references already shared with the event-tap
// thread; the controller holds no mutable state of its own, so it is safe to hand to the
// main-actor verification closure used by the optional Cmd+W path.
final class InterceptionController: @unchecked Sendable {
    private let settingsStore: SettingsStore
    private let eventMonitor: EventMonitor
    private let axInspector: AXInspecting
    private let windowCountingService: WindowCountingService
    private let windowClassifier: WindowClassifier
    private let decisionEngine: DecisionEngine
    private let policyResolver: AppPolicyResolver
    private let actionExecutor: ActionExecutor
    private let diagnosticsStore: DiagnosticsStore
    private let selfBundleID = Bundle.main.bundleIdentifier

    init(
        settingsStore: SettingsStore,
        eventMonitor: EventMonitor,
        axInspector: AXInspecting,
        windowCountingService: WindowCountingService,
        windowClassifier: WindowClassifier,
        decisionEngine: DecisionEngine,
        policyResolver: AppPolicyResolver,
        actionExecutor: ActionExecutor,
        diagnosticsStore: DiagnosticsStore
    ) {
        self.settingsStore = settingsStore
        self.eventMonitor = eventMonitor
        self.axInspector = axInspector
        self.windowCountingService = windowCountingService
        self.windowClassifier = windowClassifier
        self.decisionEngine = decisionEngine
        self.policyResolver = policyResolver
        self.actionExecutor = actionExecutor
        self.diagnosticsStore = diagnosticsStore
    }

    @discardableResult
    func start() -> Result<Void, EventMonitorError> {
        eventMonitor.start { [weak self] type, event in
            self?.handle(type: type, event: event) ?? .passThrough
        }
    }

    func stop() {
        eventMonitor.stop()
    }

    private func handle(type: CGEventType, event: CGEvent) -> EventDisposition {
        if type == .keyDown {
            handleKeyDown(event: event)
            return .passThrough
        }
        return handleCloseButton(event: event)
    }

    private func handleCloseButton(event: CGEvent) -> EventDisposition {
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

        let closedWindowIsStandard = windowClassifier.isStandardWindow(
            role: axInspector.role(of: window),
            subrole: axInspector.subrole(of: window)
        )
        if logVerbose {
            Log.interception.debug("Closed window standard=\(closedWindowIsStandard)")
        }

        let context = DecisionContext(
            isEnabled: settings.isEnabled,
            isPaused: settings.isPaused,
            permissionGranted: true,
            resolvedPolicy: resolved,
            windowCount: windowCountResult,
            closedWindowIsStandard: closedWindowIsStandard
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

    /// `kVK_ANSI_W` — the virtual key code for the W key.
    private static let wKeyCode: Int64 = 13

    /// Optional, experimental Cmd+W path (issue #1). The keystroke is never swallowed; we
    /// let the frontmost app close its own window, then re-check the window count after a
    /// short delay and request a normal quit only if the last normal window is gone.
    private func handleKeyDown(event: CGEvent) {
        // Cheap event checks first — this runs for every keystroke, so avoid copying
        // settings until we know it is actually a plain Cmd+W.
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.wKeyCode else { return }
        let flags = event.flags
        guard flags.contains(.maskCommand),
              !flags.contains(.maskShift),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskControl) else { return }

        let settings = settingsStore.settings
        guard settings.isEnabled, !settings.isPaused, settings.enableCmdWHandling else { return }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return }
        let pid = app.processIdentifier

        // Never act on SmartClose itself, and honor the resolved Cmd+W policy.
        guard bundleID != selfBundleID else { return }
        guard policyResolver.cmdWEnabled(bundleID: bundleID, settings: settings) else { return }

        // Count windows BEFORE the app handles Cmd+W. The keystroke has only been observed
        // (the event tap runs before delivery), so the target window is still open here. Only
        // arm when there is exactly one confidently-classified normal window — a plausible
        // "last window" — otherwise Cmd+W is just closing a tab/secondary window and we leave
        // it alone.
        let windowsBefore = windowCountingService.countWindows(for: pid, appIsHidden: app.isHidden, settings: settings)
        guard let windowsBefore, windowsBefore.count == 1, !windowsBefore.ambiguous else {
            if settings.debugLoggingLevel == .verbose {
                Log.interception.debug("Cmd+W not armed bundle=\(bundleID) before=\(windowsBefore?.count ?? -1) ambiguous=\(windowsBefore?.ambiguous ?? true)")
            }
            return
        }

        let verificationPolicy = CmdWVerificationPolicy(configuredInitialDelay: settings.cmdWVerifyDelay)
        let delay = verificationPolicy.initialDelay
        if settings.debugLoggingLevel == .info || settings.debugLoggingLevel == .verbose {
            Log.interception.info("Cmd+W armed bundle=\(bundleID); verifying after \(delay)s")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.verifyAndMaybeQuitAfterCmdW(
                pid: pid,
                bundleID: bundleID,
                windowsBefore: windowsBefore,
                settings: settings,
                verificationPolicy: verificationPolicy,
                elapsed: delay,
                samples: []
            )
        }
    }

    private func verifyAndMaybeQuitAfterCmdW(
        pid: pid_t,
        bundleID: String,
        windowsBefore: WindowCountResult,
        settings: Settings,
        verificationPolicy: CmdWVerificationPolicy,
        elapsed: TimeInterval,
        samples: [WindowCountResult?]
    ) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            // The app already quit on its own — nothing to do.
            return
        }

        let windowsAfter = windowCountingService.countWindows(for: pid, appIsHidden: app.isHidden, settings: settings)
        let samples = samples + [windowsAfter]
        let decision = decisionEngine.decideAfterCmdW(
            isEnabled: settings.isEnabled,
            isPaused: settings.isPaused,
            permissionGranted: true,
            resolvedPolicy: policyResolver.resolve(bundleID: bundleID, settings: settings),
            windowsBefore: windowsBefore,
            windowsAfter: windowsAfter
        )
        if settings.debugLoggingLevel == .info || settings.debugLoggingLevel == .verbose {
            Log.interception.info("Cmd+W decision action=\(decision.action.rawValue) reason=\(decision.reason) bundle=\(bundleID)")
        }

        if decision.action == .requestQuit {
            let success = actionExecutor.requestQuit(pid: pid)
            logDecision(
                app: app,
                bundleID: bundleID,
                decision: decision,
                windowCount: windowsAfter?.count,
                ignoredCount: windowsAfter?.ignoredCount,
                actionTaken: success ? "Requested quit (Cmd+W)" : "Quit request failed (Cmd+W)",
                details: cmdWVerificationDetails(windowsBefore: windowsBefore, samples: samples, elapsed: elapsed)
            )
        } else if let nextDelay = verificationPolicy.nextDelay(afterElapsed: elapsed, latestResult: windowsAfter) {
            let nextElapsed = elapsed + nextDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + nextDelay) { [weak self] in
                self?.verifyAndMaybeQuitAfterCmdW(
                    pid: pid,
                    bundleID: bundleID,
                    windowsBefore: windowsBefore,
                    settings: settings,
                    verificationPolicy: verificationPolicy,
                    elapsed: nextElapsed,
                    samples: samples
                )
            }
        } else {
            logDecision(
                app: app,
                bundleID: bundleID,
                decision: decision,
                windowCount: windowsAfter?.count,
                ignoredCount: windowsAfter?.ignoredCount,
                actionTaken: "Passed through (Cmd+W)",
                details: cmdWVerificationDetails(windowsBefore: windowsBefore, samples: samples, elapsed: elapsed)
            )
        }
    }

    private func cmdWVerificationDetails(
        windowsBefore: WindowCountResult,
        samples: [WindowCountResult?],
        elapsed: TimeInterval
    ) -> String {
        let before = windowCountSummary(windowsBefore)
        let after = samples.enumerated()
            .map { index, result in
                "after[\(index + 1)]=\(windowCountSummary(result))"
            }
            .joined(separator: "; ")
        return "Cmd+W verify before=\(before); \(after); elapsed=\(String(format: "%.2f", elapsed))s"
    }

    private func windowCountSummary(_ result: WindowCountResult?) -> String {
        guard let result else { return "unavailable" }
        var parts = [
            "count \(result.count)",
            "ignored \(result.ignoredCount)",
            "ambiguous \(result.ambiguous)"
        ]
        if !result.reasons.isEmpty {
            parts.append("reasons \(result.reasons.joined(separator: ", "))")
        }
        return parts.joined(separator: ", ")
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
        actionTaken: String,
        details: String? = nil
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
            actionTaken: actionTaken,
            details: details
        )
        let store = diagnosticsStore
        Task { @MainActor in
            store.append(event: event)
        }
    }
}
