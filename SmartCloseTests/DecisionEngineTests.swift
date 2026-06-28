import XCTest
@testable import SmartClose

final class DecisionEngineTests: XCTestCase {
    private func decideClose(
        isEnabled: Bool = true,
        isPaused: Bool = false,
        behavior: CloseBehavior = .smartClose,
        isExcluded: Bool = false,
        count: Int,
        ambiguous: Bool = false,
        closedWindowIsStandard: Bool = true
    ) -> DecisionResult {
        DecisionEngine().decide(context: DecisionContext(
            isEnabled: isEnabled,
            isPaused: isPaused,
            permissionGranted: true,
            resolvedPolicy: ResolvedPolicy(behavior: behavior, matchedRule: nil, isExcluded: isExcluded),
            windowCount: WindowCountResult(count: count, ambiguous: ambiguous, ignoredCount: 0, reasons: []),
            closedWindowIsStandard: closedWindowIsStandard
        ))
    }

    func testLastWindowRequestsQuit() {
        XCTAssertEqual(decideClose(count: 1).action, .requestQuit)
    }

    func testMultipleWindowsPassThrough() {
        XCTAssertEqual(decideClose(count: 2).action, .passThrough)
    }

    func testDisabledPassThrough() {
        XCTAssertEqual(decideClose(isEnabled: false, count: 1).action, .passThrough)
    }

    func testAmbiguousPassThrough() {
        XCTAssertEqual(decideClose(count: 1, ambiguous: true).action, .passThrough)
    }

    // Regression for issue #6: clicking the close button of an auxiliary window (Find &
    // Replace, a dialog, a floating panel) must never quit, even when the app has exactly one
    // standard window remaining.
    func testNonStandardClosedWindowPassesThroughEvenAtLastWindow() {
        XCTAssertEqual(decideClose(count: 1, closedWindowIsStandard: false).action, .passThrough)
    }

    func testStandardClosedWindowQuitsAtLastWindow() {
        XCTAssertEqual(decideClose(count: 1, closedWindowIsStandard: true).action, .requestQuit)
    }

    // MARK: - Cmd+W path (decideAfterCmdW)

    private func windowCount(_ count: Int, ambiguous: Bool = false) -> WindowCountResult {
        WindowCountResult(count: count, ambiguous: ambiguous, ignoredCount: 0, reasons: [])
    }

    private func decideCmdW(
        isEnabled: Bool = true,
        isPaused: Bool = false,
        behavior: CloseBehavior = .smartClose,
        isExcluded: Bool = false,
        before: WindowCountResult?,
        after: WindowCountResult?
    ) -> DecisionResult {
        DecisionEngine().decideAfterCmdW(
            isEnabled: isEnabled,
            isPaused: isPaused,
            permissionGranted: true,
            resolvedPolicy: ResolvedPolicy(behavior: behavior, matchedRule: nil, isExcluded: isExcluded),
            windowsBefore: before,
            windowsAfter: after
        )
    }

    // Regression test for issue #3: an app with no windows reports count 0, but the window
    // counter flags that result `ambiguous` ("No windows returned"). The Cmd+W path must still
    // quit — it was passing through on the ambiguous flag, so Cmd+W never quit any app.
    func testCmdWQuitsWhenLastWindowGoneEvenThoughAfterCountIsAmbiguous() {
        let result = decideCmdW(before: windowCount(1), after: windowCount(0, ambiguous: true))
        XCTAssertEqual(result.action, .requestQuit)
    }

    func testCmdWQuitsWhenLastWindowGone() {
        XCTAssertEqual(decideCmdW(before: windowCount(1), after: windowCount(0)).action, .requestQuit)
    }

    func testCmdWPassesThroughWhenWindowStillOpen() {
        XCTAssertEqual(decideCmdW(before: windowCount(1), after: windowCount(1)).action, .passThrough)
        XCTAssertEqual(decideCmdW(before: windowCount(1), after: windowCount(2)).action, .passThrough)
    }

    func testCmdWCanQuitAfterTransientNonZeroRetrySample() {
        let firstSample = decideCmdW(before: windowCount(1), after: windowCount(1))
        let secondSample = decideCmdW(before: windowCount(1), after: windowCount(0))

        XCTAssertEqual(firstSample.action, .passThrough)
        XCTAssertEqual(firstSample.reason, "Window still open after Cmd+W")
        XCTAssertEqual(secondSample.action, .requestQuit)
    }

    func testCmdWVerificationPolicyRetriesUntilClosedOrTimedOut() {
        let policy = CmdWVerificationPolicy(
            configuredInitialDelay: 0.25,
            retryInterval: 0.2,
            maxDuration: 1.0
        )

        XCTAssertEqual(policy.initialDelay, 0.25, accuracy: 0.0001)
        XCTAssertEqual(policy.maxDuration, 1.0, accuracy: 0.0001)
        XCTAssertEqual(policy.nextDelay(afterElapsed: 0.25, latestResult: windowCount(1)) ?? -1, 0.2, accuracy: 0.0001)
        XCTAssertNil(policy.nextDelay(afterElapsed: 0.45, latestResult: windowCount(0)))
        XCTAssertNil(policy.nextDelay(afterElapsed: 1.0, latestResult: windowCount(1)))
    }

    func testCmdWVerificationPolicyKeepsCustomInitialDelayInsideTimeout() {
        let policy = CmdWVerificationPolicy(
            configuredInitialDelay: 1.5,
            retryInterval: 0.2,
            maxDuration: 1.0
        )

        XCTAssertEqual(policy.initialDelay, 1.5, accuracy: 0.0001)
        XCTAssertEqual(policy.maxDuration, 1.5, accuracy: 0.0001)
        XCTAssertNil(policy.nextDelay(afterElapsed: 1.5, latestResult: windowCount(1)))
    }

    func testCmdWNotArmedUnlessExactlyOneConfidentWindowBefore() {
        // Multiple windows before → Cmd+W only closed a secondary window; never quit.
        XCTAssertEqual(decideCmdW(before: windowCount(2), after: windowCount(0)).action, .passThrough)
        // No window before → nothing to close.
        XCTAssertEqual(decideCmdW(before: windowCount(0), after: windowCount(0)).action, .passThrough)
        // Ambiguous before → not confident there was a single normal window.
        XCTAssertEqual(decideCmdW(before: windowCount(1, ambiguous: true), after: windowCount(0)).action, .passThrough)
        // Missing before.
        XCTAssertEqual(decideCmdW(before: nil, after: windowCount(0)).action, .passThrough)
    }

    func testCmdWPassesThroughWhenAfterCountUnavailable() {
        XCTAssertEqual(decideCmdW(before: windowCount(1), after: nil).action, .passThrough)
    }

    func testCmdWRespectsDisabledPausedAndPolicy() {
        XCTAssertEqual(decideCmdW(isEnabled: false, before: windowCount(1), after: windowCount(0)).action, .passThrough)
        XCTAssertEqual(decideCmdW(isPaused: true, before: windowCount(1), after: windowCount(0)).action, .passThrough)
        XCTAssertEqual(decideCmdW(behavior: .disabled, isExcluded: true, before: windowCount(1), after: windowCount(0)).action, .passThrough)
        XCTAssertEqual(decideCmdW(behavior: .alwaysNormalClose, before: windowCount(1), after: windowCount(0)).action, .passThrough)
    }
}

@MainActor
final class PermissionManagerTests: XCTestCase {
    func testFirstPromptDoesNotOpenSettings() {
        var currentDate = Date()
        var settingsOpenCount = 0
        var promptCount = 0

        let manager = PermissionManager(
            statusChecker: { false },
            promptRequester: {
                promptCount += 1
                return false
            },
            settingsOpener: { _ in settingsOpenCount += 1 },
            now: { currentDate },
            appIdentity: AppIdentitySnapshot(
                bundleID: "com.smartclose.app",
                codeSigningIdentifier: "com.smartclose.app",
                bundlePath: "/Applications/SmartClose.app"
            ),
            testState: nil
        )

        manager.requestAccess()

        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(settingsOpenCount, 0)
        XCTAssertEqual(manager.rowStatus, .requesting)
        XCTAssertEqual(manager.row.action, .none)
    }

    func testPromptFallsBackToOpenSettingsAfterTimeout() {
        var currentDate = Date()

        let manager = PermissionManager(
            statusChecker: { false },
            promptRequester: { false },
            settingsOpener: { _ in },
            now: { currentDate },
            appIdentity: AppIdentitySnapshot(
                bundleID: "com.smartclose.app",
                codeSigningIdentifier: "com.smartclose.app",
                bundlePath: "/Applications/SmartClose.app"
            ),
            testState: nil
        )

        manager.requestAccess()
        currentDate = currentDate.addingTimeInterval(5)
        manager.refreshStatus()

        XCTAssertEqual(manager.rowStatus, .missing)
        XCTAssertEqual(manager.row.action, .openSettings)
    }

    func testGrantedPreflightImmediatelyTurnsRowGreen() {
        let manager = PermissionManager(
            statusChecker: { true },
            promptRequester: { true },
            settingsOpener: { _ in },
            now: Date.init,
            appIdentity: AppIdentitySnapshot(
                bundleID: "com.smartclose.app",
                codeSigningIdentifier: "com.smartclose.app",
                bundlePath: "/Applications/SmartClose.app"
            ),
            testState: nil
        )

        XCTAssertTrue(manager.isGranted)
        XCTAssertEqual(manager.rowStatus, .granted)
        XCTAssertEqual(manager.row.action, .none)
    }

    func testRecoveryStateAppearsAfterGrantWhenServiceFails() {
        let manager = InputMonitoringManager(
            statusChecker: { true },
            promptRequester: { true },
            settingsOpener: { _ in },
            now: Date.init,
            appIdentity: AppIdentitySnapshot(
                bundleID: "com.smartclose.app",
                codeSigningIdentifier: "com.smartclose.app",
                bundlePath: "/Applications/SmartClose.app"
            ),
            testState: nil
        )

        manager.setRecoveryMessage("Relaunch SmartClose to rebuild the global event tap.")

        XCTAssertTrue(manager.isGranted)
        XCTAssertEqual(manager.rowStatus, .recoveryNeeded)
        XCTAssertEqual(manager.row.action, .relaunchApp)
    }
}

final class OnboardingProgressTests: XCTestCase {
    func testOneMissingPermissionResumesChecklist() {
        let settings = Settings.default

        let step = OnboardingProgress.resolvedStep(for: settings, permissionsGranted: false)

        XCTAssertEqual(step, .permissions)
    }

    func testGrantedPermissionsResumeQuickSetup() {
        let settings = Settings.default

        let step = OnboardingProgress.resolvedStep(for: settings, permissionsGranted: true)

        XCTAssertEqual(step, .quickSetup)
    }

    func testCompletedOnboardingSkipsToAllSet() {
        var settings = Settings.default
        settings.firstRunCompleted = true

        let step = OnboardingProgress.resolvedStep(for: settings, permissionsGranted: true)

        XCTAssertEqual(step, .allSet)
    }
}

@MainActor
final class PermissionDiagnosticsTests: XCTestCase {
    func testDiagnosticsSnapshotKeepsBundleAndCodeSigningIdentifiers() {
        let store = DiagnosticsStore()
        let snapshot = PermissionDiagnosticsSnapshot(
            appIdentity: AppIdentitySnapshot(
                bundleID: "com.smartclose.app",
                codeSigningIdentifier: "com.smartclose.app",
                bundlePath: "/Applications/SmartClose.app"
            ),
            accessibilityRow: PermissionRowModel(
                kind: .accessibility,
                status: .granted,
                action: .none,
                message: "SmartClose can inspect windows."
            ),
            inputMonitoringRow: PermissionRowModel(
                kind: .inputMonitoring,
                status: .missing,
                action: .openSettings,
                message: "Enable SmartClose manually in System Settings."
            ),
            eventMonitorState: .failed,
            eventMonitorMessage: EventMonitorError.tapCreationFailed.message
        )

        store.updatePermissionSnapshot(snapshot)

        XCTAssertEqual(store.permissionSnapshot.appIdentity.bundleID, "com.smartclose.app")
        XCTAssertEqual(store.permissionSnapshot.appIdentity.codeSigningIdentifier, "com.smartclose.app")
        XCTAssertEqual(store.permissionSnapshot.eventMonitorMessage, EventMonitorError.tapCreationFailed.message)
    }
}
