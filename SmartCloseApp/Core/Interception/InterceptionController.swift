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

/// What started a document check for an app using the "Quit when last document closes" rule.
enum DocumentCloseTrigger: String {
    case closeButton
    case cmdW
}

// All stored dependencies are immutable `let` references already shared with the event-tap
// thread. The only mutable state (document-check tokens, the close-button miss log time and the
// set of apps already asked for Automation) is guarded by locks, so the controller is safe to
// hand to the verification closures used by the Cmd+W and document paths.
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
    private let ownWindowHitTester: OwnWindowHitTester
    private let hostAppResolver: HostAppResolver
    private let documentCounter: DocumentCounting
    private let documentVerificationPolicy: DocumentVerificationPolicy
    private let selfBundleID = Bundle.main.bundleIdentifier
    /// Apple Events block until the app replies, so document checks run on their own queue,
    /// never on the event-tap thread or the main thread.
    private let documentQueue = DispatchQueue(label: "SmartClose.DocumentCount", qos: .userInitiated)
    private let documentTokens = DocumentCheckTokens()
    private let stateLock = NSLock()
    /// Last time a missed close button in a document-rule app was written to Diagnostics.
    private var lastCloseButtonMissLog: Date?
    /// Apps already asked for Automation access after a check reported it missing.
    private var automationRequestedBundleIDs: Set<String> = []
    /// Size of the top-left window area that holds the traffic-light buttons. Used only to skip
    /// Accessibility calls for clicks that cannot be on a close button.
    static let windowControlsArea = CGSize(width: 120, height: 80)

    init(
        settingsStore: SettingsStore,
        eventMonitor: EventMonitor,
        axInspector: AXInspecting,
        windowCountingService: WindowCountingService,
        windowClassifier: WindowClassifier,
        decisionEngine: DecisionEngine,
        policyResolver: AppPolicyResolver,
        actionExecutor: ActionExecutor,
        diagnosticsStore: DiagnosticsStore,
        ownWindowHitTester: OwnWindowHitTester = OwnWindowHitTester(),
        hostAppResolver: HostAppResolver = HostAppResolver(),
        documentCounter: DocumentCounting = AppleEventDocumentCounter(),
        documentVerificationPolicy: DocumentVerificationPolicy = DocumentVerificationPolicy()
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
        self.ownWindowHitTester = ownWindowHitTester
        self.hostAppResolver = hostAppResolver
        self.documentCounter = documentCounter
        self.documentVerificationPolicy = documentVerificationPolicy
    }

    @discardableResult
    func start() -> Result<Void, EventMonitorError> {
        eventMonitor.start { [weak self] type, event in
            self?.handle(type: type, event: event) ?? .passThrough
        }
    }

    func stop() {
        eventMonitor.stop()
        documentTokens.cancelAll()
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
        // Exclude SmartClose itself before touching Accessibility: an AX hit-test on our own
        // window runs SwiftUI on this event-tap thread and traps on macOS 27 (issue #20).
        guard !ownWindowHitTester.isOwnWindow(at: point) else {
            if logVerbose { Log.interception.debug("Pass-through: click on SmartClose's own window") }
            return .passThrough
        }
        guard let hitElement = axInspector.elementAtScreenPoint(point) else {
            if logVerbose { Log.interception.debug("Pass-through: no AX element at point") }
            return .passThrough
        }
        let element: AXUIElement
        var knownWindow: AXUIElement?
        if isCloseButton(element: hitElement) {
            element = hitElement
        } else if let fallback = documentAwareCloseButton(at: point, hitElement: hitElement, settings: settings) {
            // Some apps' hit-test does not land on the close button (Adobe Illustrator reported no
            // close at all, issue #29). Only for apps the user opted into the document rule. Keep
            // the window the button came from: custom AX trees may not link the button back to it.
            if logVerbose { Log.interception.debug("Close button found through the window's AXCloseButton frame") }
            element = fallback.closeButton
            knownWindow = fallback.window
        } else {
            if logVerbose { Log.interception.debug("Pass-through: element is not close button") }
            return .passThrough
        }
        guard let window = knownWindow ?? axInspector.windowForElement(element) else {
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

        // Docker Desktop-style apps keep their windows in a UI app nested inside a faceless host;
        // rules written for the host must apply too (issue #25).
        let hostBundleID = hostAppResolver.hostBundleID(forAppAt: runningApp.bundleURL)
        let resolved = policyResolver.resolve(bundleID: bundleID, hostBundleID: hostBundleID, settings: settings)
        let policyDetails = Self.hostMatchDetails(resolved)
        if resolved.isExcluded {
            if logInfo { Log.interception.info("Pass-through: excluded by policy (\(resolved.matchedRule ?? "none")) bundle=\(bundleID) host=\(hostBundleID ?? "none")") }
            logDecision(
                app: runningApp,
                bundleID: bundleID,
                decision: DecisionResult(action: .passThrough, reason: String(localized: "Excluded by policy")),
                windowCount: nil,
                ignoredCount: nil,
                actionTaken: String(localized: "None"),
                details: policyDetails
            )
            return .passThrough
        }

        if resolved.behavior == .documentAware {
            return handleDocumentAwareClose(
                window: window,
                pid: pid,
                runningApp: runningApp,
                bundleID: bundleID,
                hostBundleID: hostBundleID,
                resolved: resolved,
                settings: settings
            )
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
        // Show why a classification was ambiguous or windows were ignored, so reports like
        // issue #30 ("Ambiguous window classification") carry the cause.
        let decisionDetails = Self.joinedDetails(policyDetails, Self.classificationDetails(windowCountResult))

        if decision.action == .requestQuit {
            let success = actionExecutor.requestQuit(pid: pid)
            logDecision(
                app: runningApp,
                bundleID: bundleID,
                decision: decision,
                windowCount: windowCountResult?.count,
                ignoredCount: windowCountResult?.ignoredCount,
                actionTaken: success ? String(localized: "Requested quit") : String(localized: "Quit request failed"),
                details: decisionDetails
            )
            return .swallow
        }

        logDecision(
            app: runningApp,
            bundleID: bundleID,
            decision: decision,
            windowCount: windowCountResult?.count,
            ignoredCount: windowCountResult?.ignoredCount,
            actionTaken: String(localized: "Passed through"),
            details: decisionDetails
        )
        return .passThrough
    }

    /// Red close button in an app using the "Quit when last document closes" rule. The click
    /// always goes through so the app closes the document itself (including any save prompt);
    /// SmartClose then asks the app how many documents remain.
    private func handleDocumentAwareClose(
        window: AXUIElement,
        pid: pid_t,
        runningApp: NSRunningApplication,
        bundleID: String,
        hostBundleID: String?,
        resolved: ResolvedPolicy,
        settings: Settings
    ) -> EventDisposition {
        let closedWindowIsStandard = windowClassifier.isStandardWindow(
            role: axInspector.role(of: window),
            subrole: axInspector.subrole(of: window)
        )
        let context = DecisionContext(
            isEnabled: settings.isEnabled,
            isPaused: settings.isPaused,
            permissionGranted: true,
            resolvedPolicy: resolved,
            windowCount: nil,
            closedWindowIsStandard: closedWindowIsStandard
        )

        if decisionEngine.shouldVerifyDocuments(context: context) {
            if settings.debugLoggingLevel == .info || settings.debugLoggingLevel == .verbose {
                Log.interception.info("Document check armed (close button) bundle=\(bundleID)")
            }
            startDocumentVerification(pid: pid, bundleID: bundleID, hostBundleID: hostBundleID, trigger: .closeButton)
            return .passThrough
        }

        logDecision(
            app: runningApp,
            bundleID: bundleID,
            decision: decisionEngine.decide(context: context),
            windowCount: nil,
            ignoredCount: nil,
            actionTaken: String(localized: "Passed through"),
            details: Self.hostMatchDetails(resolved)
        )
        return .passThrough
    }

    /// For apps using the document rule only: when the hit-test landed on something other than
    /// the close button, checks whether the click is inside the frame the window itself reports
    /// for its `AXCloseButton`. Skipped entirely unless a per-app rule uses the document rule, and
    /// clicks outside the top-left window-controls area of the app's frontmost window under the
    /// pointer (from the WindowServer list, no Accessibility) never reach Accessibility.
    private func documentAwareCloseButton(at point: CGPoint, hitElement: AXUIElement, settings: Settings) -> (closeButton: AXUIElement, window: AXUIElement)? {
        guard settings.perAppRules.values.contains(.quitWhenLastDocumentCloses) else { return nil }
        guard let pid = axInspector.pid(of: hitElement),
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              bundleID != selfBundleID else { return nil }
        let hostBundleID = hostAppResolver.hostBundleID(forAppAt: app.bundleURL)
        let resolved = policyResolver.resolve(bundleID: bundleID, hostBundleID: hostBundleID, settings: settings)
        guard !resolved.isExcluded, resolved.behavior == .documentAware else { return nil }
        guard Self.isInWindowControlsArea(point: point, pid: pid, windows: OwnWindowHitTester.onScreenWindows()) else { return nil }

        let window = axInspector.windowForElement(hitElement)
        let closeButton = window.flatMap { axInspector.closeButton(ofWindow: $0) }
        let frame = closeButton.flatMap { axInspector.frame(of: $0) }
        if let window, let closeButton, Self.closeButtonFrame(frame, contains: point) {
            return (closeButton, window)
        }

        // Record what the app exposed, so a report like issue #29 shows why no close was seen.
        logCloseButtonMiss(
            app: app,
            bundleID: bundleID,
            details: "Hit element role=\(axInspector.role(of: hitElement) ?? "none") subrole=\(axInspector.subrole(of: hitElement) ?? "none"); "
                + "window=\(window == nil ? "none" : "found"); AXCloseButton=\(closeButton == nil ? "none" : "found"); "
                + "frame=\(frame.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "none")"
        )
        return nil
    }

    /// Whether `point` lies in the top-left window-controls area of the frontmost on-screen window
    /// under it, and that window belongs to `pid`. `windows` is front-to-back WindowServer order.
    static func isInWindowControlsArea(point: CGPoint, pid: pid_t, windows: [OnScreenWindow]) -> Bool {
        guard let window = windows.first(where: { $0.bounds.contains(point) }), window.ownerPID == pid else {
            return false
        }
        return point.x - window.bounds.minX < windowControlsArea.width
            && point.y - window.bounds.minY < windowControlsArea.height
    }

    /// At most one Diagnostics entry every 10 seconds.
    private func logCloseButtonMiss(app: NSRunningApplication, bundleID: String, details: String) {
        let now = Date()
        stateLock.lock()
        if let last = lastCloseButtonMissLog, now.timeIntervalSince(last) < 10 {
            stateLock.unlock()
            return
        }
        lastCloseButtonMissLog = now
        stateLock.unlock()
        logDecision(
            app: app,
            bundleID: bundleID,
            decision: DecisionResult(action: .passThrough, reason: String(localized: "Close button not found")),
            windowCount: nil,
            ignoredCount: nil,
            actionTaken: String(localized: "None"),
            details: details
        )
    }

    /// Asks once per session for Automation access to an app whose check reported it missing.
    private func requestAutomationOnce(bundleID: String) {
        stateLock.lock()
        let isNew = automationRequestedBundleIDs.insert(bundleID).inserted
        stateLock.unlock()
        if isNew {
            AutomationPermission.request(bundleIDs: [bundleID])
        }
    }

    /// Whether `point` is inside a close button's Accessibility frame. Empty or missing frames
    /// never match.
    static func closeButtonFrame(_ frame: CGRect?, contains point: CGPoint) -> Bool {
        guard let frame, frame.width > 0, frame.height > 0 else { return false }
        return frame.contains(point)
    }

    // MARK: - Document checks ("Quit when last document closes")

    private func startDocumentVerification(pid: pid_t, bundleID: String, hostBundleID: String?, trigger: DocumentCloseTrigger) {
        let token = documentTokens.begin(pid: pid)

        let startedAt = Date()
        documentQueue.asyncAfter(deadline: .now() + documentVerificationPolicy.initialDelay) { [weak self] in
            self?.verifyDocuments(
                pid: pid,
                bundleID: bundleID,
                hostBundleID: hostBundleID,
                trigger: trigger,
                token: token,
                startedAt: startedAt,
                samples: []
            )
        }
    }

    private func isCurrentDocumentCheck(pid: pid_t, token: UUID) -> Bool {
        documentTokens.isCurrent(pid: pid, token: token)
    }

    private func finishDocumentCheck(pid: pid_t, token: UUID) {
        documentTokens.finish(pid: pid, token: token)
    }

    private func verifyDocuments(
        pid: pid_t,
        bundleID: String,
        hostBundleID: String?,
        trigger: DocumentCloseTrigger,
        token: UUID,
        startedAt: Date,
        samples: [DocumentCountResult]
    ) {
        guard isCurrentDocumentCheck(pid: pid, token: token) else { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            // The app already quit on its own — nothing to do.
            finishDocumentCheck(pid: pid, token: token)
            return
        }

        // Do not even ask the app once SmartClose is paused or disabled or the rule changed.
        guard documentRuleStillApplies(bundleID: bundleID, hostBundleID: hostBundleID, settings: settingsStore.settings) else {
            finishDocumentCheck(pid: pid, token: token)
            return
        }
        let result = documentCounter.documentCount(for: pid, timeout: documentVerificationPolicy.requestTimeout)
        guard isCurrentDocumentCheck(pid: pid, token: token) else { return }
        // Re-read settings after the blocking request, so a pause during it is honored.
        let settings = settingsStore.settings

        if result == .failed(DocumentCountResult.consentRequired) {
            requestAutomationOnce(bundleID: bundleID)
        }

        // Zero documents is not enough on its own: at most one standard window (the empty
        // application frame) may remain. Only read when it matters, to spare Accessibility calls.
        var remainingWindows: Int?
        if result == .count(0) {
            remainingWindows = windowClassifier.classify(
                windows: axInspector.windowInfos(for: pid),
                appIsHidden: app.isHidden,
                settings: settings
            ).count
        }

        let samples = samples + [result]
        let elapsed = Date().timeIntervalSince(startedAt)
        let resolved = policyResolver.resolve(bundleID: bundleID, hostBundleID: hostBundleID, settings: settings)
        let decision = decisionEngine.decideAfterDocumentClose(
            isEnabled: settings.isEnabled,
            isPaused: settings.isPaused,
            permissionGranted: true,
            resolvedPolicy: resolved,
            documentCount: result,
            remainingStandardWindows: remainingWindows
        )
        let logInfo = settings.debugLoggingLevel == .info || settings.debugLoggingLevel == .verbose
        if logInfo {
            Log.interception.info("Document check \(trigger.rawValue) result=\(result.summary, privacy: .public) action=\(decision.action.rawValue) bundle=\(bundleID)")
        }

        if decision.action == .requestQuit {
            finishDocumentCheck(pid: pid, token: token)
            let success = actionExecutor.requestQuit(pid: pid)
            logDecision(
                app: app,
                bundleID: bundleID,
                decision: decision,
                windowCount: nil,
                ignoredCount: nil,
                actionTaken: trigger == .cmdW
                    ? (success ? String(localized: "Requested quit (Cmd+W)") : String(localized: "Quit request failed (Cmd+W)"))
                    : (success ? String(localized: "Requested quit") : String(localized: "Quit request failed")),
                details: Self.joinedDetails(
                    Self.hostMatchDetails(resolved),
                    Self.documentCheckDetails(trigger: trigger, samples: samples, elapsed: elapsed, remainingWindows: remainingWindows)
                )
            )
            return
        }

        // Keep checking only while the rule still applies and SmartClose is active.
        let stillApplies = Self.documentRuleApplies(resolved: resolved, settings: settings)
        if stillApplies, let nextDelay = documentVerificationPolicy.nextDelay(afterElapsed: elapsed, latestResult: result) {
            documentQueue.asyncAfter(deadline: .now() + nextDelay) { [weak self] in
                self?.verifyDocuments(
                    pid: pid,
                    bundleID: bundleID,
                    hostBundleID: hostBundleID,
                    trigger: trigger,
                    token: token,
                    startedAt: startedAt,
                    samples: samples
                )
            }
            return
        }

        finishDocumentCheck(pid: pid, token: token)
        logDecision(
            app: app,
            bundleID: bundleID,
            decision: decision,
            windowCount: nil,
            ignoredCount: nil,
            actionTaken: trigger == .cmdW ? String(localized: "Passed through (Cmd+W)") : String(localized: "Passed through"),
            details: Self.joinedDetails(
                Self.hostMatchDetails(resolved),
                Self.documentCheckDetails(trigger: trigger, samples: samples, elapsed: elapsed, remainingWindows: remainingWindows)
            )
        )
    }

    private func documentRuleStillApplies(bundleID: String, hostBundleID: String?, settings: Settings) -> Bool {
        Self.documentRuleApplies(
            resolved: policyResolver.resolve(bundleID: bundleID, hostBundleID: hostBundleID, settings: settings),
            settings: settings
        )
    }

    static func documentRuleApplies(resolved: ResolvedPolicy, settings: Settings) -> Bool {
        settings.isEnabled && !settings.isPaused && !resolved.isExcluded && resolved.behavior == .documentAware
    }

    static func documentCheckDetails(
        trigger: DocumentCloseTrigger,
        samples: [DocumentCountResult],
        elapsed: TimeInterval,
        remainingWindows: Int? = nil
    ) -> String {
        let source = trigger == .cmdW ? "Cmd+W" : "close button"
        let checks = samples.enumerated()
            .map { index, result in "check[\(index + 1)]=\(result.summary)" }
            .joined(separator: "; ")
        let windows = remainingWindows.map { "; standard windows left \($0)" } ?? ""
        return "Document check after \(source): \(checks)\(windows); elapsed=\(String(format: "%.2f", elapsed))s"
    }

    /// Window classification reasons worth showing in diagnostics, or nil when there are none.
    /// Repeated reasons (one per window) are collapsed with a count.
    static func classificationDetails(_ result: WindowCountResult?) -> String? {
        guard let result, !result.reasons.isEmpty else { return nil }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for reason in result.reasons {
            if counts[reason] == nil { order.append(reason) }
            counts[reason, default: 0] += 1
        }
        let collapsed = order.map { reason in
            let count = counts[reason] ?? 1
            return count > 1 ? "\(reason) (×\(count))" : reason
        }
        return "Window classification: \(collapsed.joined(separator: ", "))"
    }

    static func joinedDetails(_ parts: String?...) -> String? {
        let present = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return present.isEmpty ? nil : present.joined(separator: " · ")
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
        let hostBundleID = hostAppResolver.hostBundleID(forAppAt: app.bundleURL)
        guard policyResolver.cmdWEnabled(bundleID: bundleID, hostBundleID: hostBundleID, settings: settings) else { return }

        // "Quit when last document closes": skip window counting entirely and ask the app for its
        // document count once it has handled Cmd+W (issues #29, #30).
        let resolved = policyResolver.resolve(bundleID: bundleID, hostBundleID: hostBundleID, settings: settings)
        if resolved.behavior == .documentAware, !resolved.isExcluded {
            // Like the red close button: Cmd+W on a panel or dialog must never quit (issue #6).
            let focusedIsStandard = axInspector.focusedWindow(ofApplication: pid).map { window in
                windowClassifier.isStandardWindow(role: axInspector.role(of: window), subrole: axInspector.subrole(of: window))
            } ?? false
            guard focusedIsStandard else {
                if settings.debugLoggingLevel == .verbose {
                    Log.interception.debug("Document check not armed (Cmd+W): focused window is not a standard window bundle=\(bundleID)")
                }
                return
            }
            if settings.debugLoggingLevel == .info || settings.debugLoggingLevel == .verbose {
                Log.interception.info("Document check armed (Cmd+W) bundle=\(bundleID)")
            }
            startDocumentVerification(pid: pid, bundleID: bundleID, hostBundleID: hostBundleID, trigger: .cmdW)
            return
        }

        // Count windows BEFORE the app handles Cmd+W. The keystroke has only been observed
        // (the event tap runs before delivery), so the target window is still open here. Arm for
        // any confidently-classified positive count and quit only if verification later reaches
        // zero. This also covers rapid multi-window sequences where Accessibility still reports
        // the penultimate, just-closed window when the final Cmd+W arrives (issue #10).
        let windowsBefore = windowCountingService.countWindows(for: pid, appIsHidden: app.isHidden, settings: settings)
        guard let windowsBefore, windowsBefore.count > 0, !windowsBefore.ambiguous else {
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
                hostBundleID: hostBundleID,
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
        hostBundleID: String?,
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
            resolvedPolicy: policyResolver.resolve(bundleID: bundleID, hostBundleID: hostBundleID, settings: settings),
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
                actionTaken: success ? String(localized: "Requested quit (Cmd+W)") : String(localized: "Quit request failed (Cmd+W)"),
                details: cmdWVerificationDetails(windowsBefore: windowsBefore, samples: samples, elapsed: elapsed)
            )
        } else if let nextDelay = verificationPolicy.nextDelay(afterElapsed: elapsed, latestResult: windowsAfter) {
            let nextElapsed = elapsed + nextDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + nextDelay) { [weak self] in
                self?.verifyAndMaybeQuitAfterCmdW(
                    pid: pid,
                    bundleID: bundleID,
                    hostBundleID: hostBundleID,
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
                actionTaken: String(localized: "Passed through (Cmd+W)"),
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

    /// Diagnostics note naming the host app whose rule decided the outcome, if any.
    static func hostMatchDetails(_ resolved: ResolvedPolicy) -> String? {
        guard let host = resolved.viaHostBundleID else { return nil }
        return "Rule matched host app \(host) (\(resolved.matchedRule ?? "default"))"
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
            appName: app.localizedName ?? String(localized: "Unknown"),
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
