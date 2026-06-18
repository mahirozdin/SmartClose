import XCTest
@testable import SmartClose

final class DecisionEngineTests: XCTestCase {
    func testLastWindowRequestsQuit() {
        let engine = DecisionEngine()
        let context = DecisionContext(
            isEnabled: true,
            isPaused: false,
            permissionGranted: true,
            resolvedPolicy: ResolvedPolicy(behavior: .smartClose, matchedRule: nil, isExcluded: false),
            windowCount: WindowCountResult(count: 1, ambiguous: false, ignoredCount: 0, reasons: [])
        )
        let result = engine.decide(context: context)
        XCTAssertEqual(result.action, .requestQuit)
    }

    func testMultipleWindowsPassThrough() {
        let engine = DecisionEngine()
        let context = DecisionContext(
            isEnabled: true,
            isPaused: false,
            permissionGranted: true,
            resolvedPolicy: ResolvedPolicy(behavior: .smartClose, matchedRule: nil, isExcluded: false),
            windowCount: WindowCountResult(count: 2, ambiguous: false, ignoredCount: 0, reasons: [])
        )
        let result = engine.decide(context: context)
        XCTAssertEqual(result.action, .passThrough)
    }

    func testDisabledPassThrough() {
        let engine = DecisionEngine()
        let context = DecisionContext(
            isEnabled: false,
            isPaused: false,
            permissionGranted: true,
            resolvedPolicy: ResolvedPolicy(behavior: .smartClose, matchedRule: nil, isExcluded: false),
            windowCount: WindowCountResult(count: 1, ambiguous: false, ignoredCount: 0, reasons: [])
        )
        let result = engine.decide(context: context)
        XCTAssertEqual(result.action, .passThrough)
    }

    func testAmbiguousPassThrough() {
        let engine = DecisionEngine()
        let context = DecisionContext(
            isEnabled: true,
            isPaused: false,
            permissionGranted: true,
            resolvedPolicy: ResolvedPolicy(behavior: .smartClose, matchedRule: nil, isExcluded: false),
            windowCount: WindowCountResult(count: 1, ambiguous: true, ignoredCount: 0, reasons: ["Missing role"])
        )
        let result = engine.decide(context: context)
        XCTAssertEqual(result.action, .passThrough)
    }

    // MARK: - Cmd+W path (decideAfterCmdW)

    private func cmdWContext(
        isEnabled: Bool = true,
        isPaused: Bool = false,
        behavior: CloseBehavior = .smartClose,
        isExcluded: Bool = false,
        count: Int,
        ambiguous: Bool = false
    ) -> DecisionContext {
        DecisionContext(
            isEnabled: isEnabled,
            isPaused: isPaused,
            permissionGranted: true,
            resolvedPolicy: ResolvedPolicy(behavior: behavior, matchedRule: nil, isExcluded: isExcluded),
            windowCount: WindowCountResult(count: count, ambiguous: ambiguous, ignoredCount: 0, reasons: [])
        )
    }

    func testCmdWQuitsWhenLastWindowGone() {
        let engine = DecisionEngine()
        let result = engine.decideAfterCmdW(context: cmdWContext(count: 0))
        XCTAssertEqual(result.action, .requestQuit)
    }

    func testCmdWPassesThroughWhenWindowsRemain() {
        // The Cmd+W path must NOT reuse the count == 1 logic of the close-button path.
        let engine = DecisionEngine()
        XCTAssertEqual(engine.decideAfterCmdW(context: cmdWContext(count: 1)).action, .passThrough)
        XCTAssertEqual(engine.decideAfterCmdW(context: cmdWContext(count: 2)).action, .passThrough)
    }

    func testCmdWPassesThroughWhenAmbiguous() {
        let engine = DecisionEngine()
        let result = engine.decideAfterCmdW(context: cmdWContext(count: 0, ambiguous: true))
        XCTAssertEqual(result.action, .passThrough)
    }

    func testCmdWRespectsDisabledPausedAndPolicy() {
        let engine = DecisionEngine()
        XCTAssertEqual(engine.decideAfterCmdW(context: cmdWContext(isEnabled: false, count: 0)).action, .passThrough)
        XCTAssertEqual(engine.decideAfterCmdW(context: cmdWContext(isPaused: true, count: 0)).action, .passThrough)
        XCTAssertEqual(engine.decideAfterCmdW(context: cmdWContext(behavior: .disabled, isExcluded: true, count: 0)).action, .passThrough)
        XCTAssertEqual(engine.decideAfterCmdW(context: cmdWContext(behavior: .alwaysNormalClose, count: 0)).action, .passThrough)
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
