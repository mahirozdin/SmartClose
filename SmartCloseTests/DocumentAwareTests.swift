import XCTest
import AppKit
@testable import SmartClose

/// "Quit when last document closes" (issues #29, #30): Adobe Illustrator keeps an empty
/// application frame open as a standard window, and InDesign's windows can classify as ambiguous,
/// so window counts cannot decide. The app's own document count does.
final class DocumentAwareTests: XCTestCase {
    private func policy(_ behavior: CloseBehavior, excluded: Bool = false) -> ResolvedPolicy {
        ResolvedPolicy(behavior: behavior, matchedRule: "com.adobe.illustrator", isExcluded: excluded)
    }

    private func decideAfterDocuments(
        isEnabled: Bool = true,
        isPaused: Bool = false,
        behavior: CloseBehavior = .documentAware,
        excluded: Bool = false,
        remainingWindows: Int? = 1,
        _ result: DocumentCountResult?
    ) -> DecisionResult {
        DecisionEngine().decideAfterDocumentClose(
            isEnabled: isEnabled,
            isPaused: isPaused,
            permissionGranted: true,
            resolvedPolicy: policy(behavior, excluded: excluded),
            documentCount: result,
            remainingStandardWindows: remainingWindows
        )
    }

    private func closeContext(
        behavior: CloseBehavior = .documentAware,
        count: Int,
        ambiguous: Bool,
        closedWindowIsStandard: Bool = true,
        isPaused: Bool = false
    ) -> DecisionContext {
        DecisionContext(
            isEnabled: true,
            isPaused: isPaused,
            permissionGranted: true,
            resolvedPolicy: policy(behavior),
            windowCount: WindowCountResult(count: count, ambiguous: ambiguous, ignoredCount: 0, reasons: []),
            closedWindowIsStandard: closedWindowIsStandard
        )
    }

    // MARK: - Policy resolution

    func testPerAppDocumentRuleResolvesToDocumentAware() {
        var settings = Settings.default
        settings.perAppRules = ["com.adobe.illustrator": .quitWhenLastDocumentCloses]

        let resolved = AppPolicyResolver().resolve(bundleID: "com.adobe.illustrator", settings: settings)

        XCTAssertEqual(resolved.behavior, .documentAware)
        XCTAssertFalse(resolved.isExcluded)
    }

    func testIgnoreListStillWinsOverDocumentRule() {
        var settings = Settings.default
        settings.ignoredBundleIDs = ["com.adobe.InDesign"]
        settings.perAppRules = ["com.adobe.InDesign": .quitWhenLastDocumentCloses]

        let resolved = AppPolicyResolver().resolve(bundleID: "com.adobe.InDesign", settings: settings)

        XCTAssertTrue(resolved.isExcluded)
    }

    func testDocumentRuleRoundTripsThroughSettings() throws {
        var settings = Settings.default
        settings.perAppRules = ["com.adobe.*": .quitWhenLastDocumentCloses]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(decoded.perAppRules["com.adobe.*"], .quitWhenLastDocumentCloses)
    }

    // MARK: - Red close button

    // Regression for #29: Illustrator's empty frame keeps the window count at 1 before and after.
    // With the document rule the click must pass through (the app closes the document itself)
    // instead of quitting on the window count.
    func testDocumentAwareCloseNeverQuitsFromWindowCount() {
        let decision = DecisionEngine().decide(context: closeContext(count: 1, ambiguous: false))

        XCTAssertEqual(decision.action, .passThrough)
        XCTAssertTrue(DecisionEngine().shouldVerifyDocuments(context: closeContext(count: 1, ambiguous: false)))
    }

    // Regression for #30: an ambiguous window classification must not block the document check.
    func testAmbiguousClassificationStillChecksDocuments() {
        let context = closeContext(count: 1, ambiguous: true)

        XCTAssertEqual(DecisionEngine().decide(context: context).action, .passThrough)
        XCTAssertTrue(DecisionEngine().shouldVerifyDocuments(context: context))
    }

    func testClosingAuxiliaryWindowDoesNotCheckDocuments() {
        let context = closeContext(count: 1, ambiguous: false, closedWindowIsStandard: false)

        XCTAssertFalse(DecisionEngine().shouldVerifyDocuments(context: context))
        XCTAssertEqual(DecisionEngine().decide(context: context).action, .passThrough)
    }

    func testOtherPoliciesDoNotCheckDocuments() {
        XCTAssertFalse(DecisionEngine().shouldVerifyDocuments(context: closeContext(behavior: .smartClose, count: 1, ambiguous: false)))
        XCTAssertFalse(DecisionEngine().shouldVerifyDocuments(context: closeContext(count: 1, ambiguous: false, isPaused: true)))
    }

    // MARK: - Document count decision

    func testZeroDocumentsRequestsQuit() {
        // Illustrator's empty Application Frame is the one standard window left (#29).
        XCTAssertEqual(decideAfterDocuments(remainingWindows: 1, .count(0)).action, .requestQuit)
        XCTAssertEqual(decideAfterDocuments(remainingWindows: 0, .count(0)).action, .requestQuit)
    }

    // An app whose dictionary has documents but that is not document-based always reports 0;
    // closing one of several windows must not quit it.
    func testZeroDocumentsWithSeveralWindowsLeftPassesThrough() {
        XCTAssertEqual(decideAfterDocuments(remainingWindows: 2, .count(0)).action, .passThrough)
        XCTAssertEqual(decideAfterDocuments(remainingWindows: nil, .count(0)).action, .passThrough)
    }

    func testRemainingDocumentsPassThrough() {
        XCTAssertEqual(decideAfterDocuments(.count(1)).action, .passThrough)
        XCTAssertEqual(decideAfterDocuments(.count(3)).action, .passThrough)
    }

    func testUnreadableCountNeverQuits() {
        XCTAssertEqual(decideAfterDocuments(nil).action, .passThrough)
        XCTAssertEqual(decideAfterDocuments(.failed(DocumentCountResult.automationDenied)).action, .passThrough)
        XCTAssertEqual(decideAfterDocuments(.failed(-1712)).action, .passThrough)
    }

    func testZeroDocumentsDoesNotQuitWhenRuleNoLongerApplies() {
        XCTAssertEqual(decideAfterDocuments(isEnabled: false, .count(0)).action, .passThrough)
        XCTAssertEqual(decideAfterDocuments(isPaused: true, .count(0)).action, .passThrough)
        XCTAssertEqual(decideAfterDocuments(excluded: true, .count(0)).action, .passThrough)
        XCTAssertEqual(decideAfterDocuments(behavior: .smartClose, .count(0)).action, .passThrough)
    }

    // MARK: - Polling schedule

    func testPollingStopsOnceDocumentsAreGone() {
        let policy = DocumentVerificationPolicy()
        XCTAssertNil(policy.nextDelay(afterElapsed: 0.3, latestResult: .count(0)))
    }

    func testPollingRetriesWhileDocumentStillOpenOrTimedOut() {
        // A save prompt keeps the document open for a moment; Adobe apps can also reply slowly.
        let policy = DocumentVerificationPolicy(initialDelay: 0.3, retryInterval: 0.3, maxDuration: 3.0)
        XCTAssertEqual(policy.nextDelay(afterElapsed: 0.3, latestResult: .count(1)) ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertEqual(policy.nextDelay(afterElapsed: 1.0, latestResult: .failed(-1712)) ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertEqual(policy.nextDelay(afterElapsed: 2.9, latestResult: .count(1)) ?? -1, 0.1, accuracy: 0.0001)
    }

    func testPollingStopsAtTimeBudgetAndOnPermanentFailures() {
        let policy = DocumentVerificationPolicy(maxDuration: 3.0)
        XCTAssertNil(policy.nextDelay(afterElapsed: 3.0, latestResult: .count(1)))
        XCTAssertNil(policy.nextDelay(afterElapsed: 0.3, latestResult: .failed(DocumentCountResult.automationDenied)))
        XCTAssertNil(policy.nextDelay(afterElapsed: 0.3, latestResult: .failed(-1708)))
        XCTAssertNil(policy.nextDelay(afterElapsed: 0.3, latestResult: .failed(-600)))
    }

    // MARK: - Close button fallback and diagnostics

    func testCloseButtonFrameHitTest() {
        let frame = CGRect(x: 10, y: 10, width: 14, height: 16)
        XCTAssertTrue(InterceptionController.closeButtonFrame(frame, contains: CGPoint(x: 15, y: 18)))
        XCTAssertFalse(InterceptionController.closeButtonFrame(frame, contains: CGPoint(x: 40, y: 18)))
        XCTAssertFalse(InterceptionController.closeButtonFrame(nil, contains: CGPoint(x: 15, y: 18)))
        XCTAssertFalse(InterceptionController.closeButtonFrame(.zero, contains: .zero))
    }

    func testAmbiguousDiagnosticsIncludeClassificationReasons() {
        let result = WindowCountResult(
            count: 1,
            ambiguous: true,
            ignoredCount: 1,
            reasons: ["Ignored auxiliary subrole: AXFloatingWindow", "Auxiliary window present alongside last standard window"]
        )

        let details = InterceptionController.joinedDetails(nil, InterceptionController.classificationDetails(result))

        XCTAssertEqual(
            details,
            "Window classification: Ignored auxiliary subrole: AXFloatingWindow, Auxiliary window present alongside last standard window"
        )
        XCTAssertNil(InterceptionController.classificationDetails(WindowCountResult(count: 1, ambiguous: false, ignoredCount: 0, reasons: [])))
    }

    func testDocumentCheckDetailsListEverySample() {
        let details = InterceptionController.documentCheckDetails(
            trigger: .cmdW,
            samples: [.count(1), .count(0)],
            elapsed: 0.6
        )
        XCTAssertEqual(details, "Document check after Cmd+W: check[1]=documents 1; check[2]=documents 0; elapsed=0.60s")
    }

    // MARK: - Reply parsing

    private func reply(_ directObject: NSAppleEventDescriptor?, error: Int32? = nil) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEAnswer),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let directObject {
            event.setParam(directObject, forKeyword: AEKeyword(keyDirectObject))
        }
        if let error {
            event.setParam(NSAppleEventDescriptor(int32: error), forKeyword: AEKeyword(keyErrorNumber))
        }
        return event
    }

    func testReplyWithIntegerIsACount() {
        XCTAssertEqual(AppleEventDocumentCounter.parseCountReply(reply(NSAppleEventDescriptor(int32: 0))), .count(0))
        XCTAssertEqual(AppleEventDocumentCounter.parseCountReply(reply(NSAppleEventDescriptor(int32: 2))), .count(2))
    }

    // Regression: `int32Value` reads anything unreadable as 0, which would have meant "quit".
    func testUnreadableReplyIsNotZeroDocuments() {
        XCTAssertEqual(AppleEventDocumentCounter.parseCountReply(reply(nil)), .failed(OSStatus(errAECoercionFail)))
        XCTAssertEqual(AppleEventDocumentCounter.parseCountReply(reply(NSAppleEventDescriptor(string: "none"))), .failed(OSStatus(errAECoercionFail)))
        XCTAssertEqual(AppleEventDocumentCounter.parseCountReply(reply(NSAppleEventDescriptor.list())), .failed(OSStatus(errAECoercionFail)))
        XCTAssertEqual(AppleEventDocumentCounter.parseCountReply(reply(NSAppleEventDescriptor.null())), .failed(OSStatus(errAECoercionFail)))
    }

    func testReplyErrorNumberIsAFailure() {
        XCTAssertEqual(AppleEventDocumentCounter.parseCountReply(reply(NSAppleEventDescriptor(int32: 0), error: -1728)), .failed(-1728))
    }

    // MARK: - Check tokens

    func testNewerCheckReplacesOlderOneForSameApp() {
        let tokens = DocumentCheckTokens()
        let first = tokens.begin(pid: 42)
        let second = tokens.begin(pid: 42)
        let other = tokens.begin(pid: 7)

        XCTAssertFalse(tokens.isCurrent(pid: 42, token: first))
        XCTAssertTrue(tokens.isCurrent(pid: 42, token: second))

        tokens.finish(pid: 42, token: first) // stale finish must not cancel the newer check
        XCTAssertTrue(tokens.isCurrent(pid: 42, token: second))

        tokens.cancelAll()
        XCTAssertFalse(tokens.isCurrent(pid: 42, token: second))
        XCTAssertFalse(tokens.isCurrent(pid: 7, token: other))
    }

    // MARK: - Window-controls pre-filter

    func testWindowControlsAreaOnlyMatchesTopLeftOfAppsFrontmostWindow() {
        let windows = [
            OnScreenWindow(ownerPID: 99, bounds: CGRect(x: 500, y: 500, width: 200, height: 200)), // other app, in front
            OnScreenWindow(ownerPID: 42, bounds: CGRect(x: 100, y: 100, width: 1000, height: 800))
        ]
        XCTAssertTrue(InterceptionController.isInWindowControlsArea(point: CGPoint(x: 112, y: 112), pid: 42, windows: windows))
        XCTAssertFalse(InterceptionController.isInWindowControlsArea(point: CGPoint(x: 600, y: 112), pid: 42, windows: windows))
        XCTAssertFalse(InterceptionController.isInWindowControlsArea(point: CGPoint(x: 112, y: 400), pid: 42, windows: windows))
        // Covered by another app's window.
        XCTAssertFalse(InterceptionController.isInWindowControlsArea(point: CGPoint(x: 510, y: 510), pid: 42, windows: windows))
        XCTAssertFalse(InterceptionController.isInWindowControlsArea(point: CGPoint(x: 112, y: 112), pid: 7, windows: windows))
    }

    // MARK: - Settings compatibility

    func testUnknownPolicyDropsOnlyThatRule() throws {
        let json = """
        { "isEnabled": true, "perAppRules": { "com.example.known": "alwaysNormalClose", "com.example.future": "someFuturePolicy" } }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.perAppRules, ["com.example.known": .alwaysNormalClose])
    }

    func testRepeatedClassificationReasonsAreCollapsed() {
        let result = WindowCountResult(
            count: 1,
            ambiguous: true,
            ignoredCount: 3,
            reasons: ["Ignored auxiliary subrole: AXFloatingWindow", "Ignored auxiliary subrole: AXFloatingWindow", "Auxiliary window present alongside last standard window"]
        )
        XCTAssertEqual(
            InterceptionController.classificationDetails(result),
            "Window classification: Ignored auxiliary subrole: AXFloatingWindow (×2), Auxiliary window present alongside last standard window"
        )
    }

    // A pause or a changed rule stops the check before (and after) the blocking Apple Event.
    func testDocumentRuleAppliesOnlyWhileActive() {
        var settings = Settings.default
        settings.isEnabled = true
        XCTAssertTrue(InterceptionController.documentRuleApplies(resolved: policy(.documentAware), settings: settings))
        XCTAssertFalse(InterceptionController.documentRuleApplies(resolved: policy(.smartClose), settings: settings))
        XCTAssertFalse(InterceptionController.documentRuleApplies(resolved: policy(.documentAware, excluded: true), settings: settings))
        settings.pauseUntil = Date().addingTimeInterval(600)
        XCTAssertFalse(InterceptionController.documentRuleApplies(resolved: policy(.documentAware), settings: settings))
        settings.pauseUntil = nil
        settings.isEnabled = false
        XCTAssertFalse(InterceptionController.documentRuleApplies(resolved: policy(.documentAware), settings: settings))
    }
}
