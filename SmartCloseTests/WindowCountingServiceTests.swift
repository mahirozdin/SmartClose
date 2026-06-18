import XCTest
@testable import SmartClose

final class WindowCountingServiceTests: XCTestCase {
    func testEmptyWindowsIsAmbiguous() {
        let mockInspector = MockAXInspector()
        mockInspector.windowInfosToReturn = []
        let classifier = WindowClassifier()
        let mockWindowServer = MockWindowServerInspector()
        let service = WindowCountingService(
            axInspector: mockInspector,
            classifier: classifier,
            windowServerInspector: mockWindowServer
        )

        let result = service.countWindows(for: 123, appIsHidden: false, settings: Settings.default)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.ambiguous ?? false)
    }

    func testQuartzFallbackResolvesMissingAXWindows() {
        let mockInspector = MockAXInspector()
        mockInspector.windowInfosToReturn = []
        let classifier = WindowClassifier()
        let mockWindowServer = MockWindowServerInspector()
        mockWindowServer.onScreenWindowCountToReturn = 1
        let service = WindowCountingService(
            axInspector: mockInspector,
            classifier: classifier,
            windowServerInspector: mockWindowServer
        )

        let result = service.countWindows(for: 123, appIsHidden: false, settings: Settings.default)
        XCTAssertEqual(result?.count, 1)
        XCTAssertFalse(result?.ambiguous ?? true)
    }

    func testQuartzFallbackResolvesAmbiguousClassification() {
        let mockInspector = MockAXInspector()
        mockInspector.windowInfosToReturn = [
            WindowInfo(
                role: kAXWindowRole as String,
                subrole: "AXUnknown",
                isMinimized: false,
                isVisible: true,
                title: "Main"
            )
        ]
        let classifier = WindowClassifier()
        let mockWindowServer = MockWindowServerInspector()
        mockWindowServer.onScreenWindowCountToReturn = 2
        let service = WindowCountingService(
            axInspector: mockInspector,
            classifier: classifier,
            windowServerInspector: mockWindowServer
        )

        let result = service.countWindows(for: 123, appIsHidden: false, settings: Settings.default)
        XCTAssertEqual(result?.count, 2)
        XCTAssertFalse(result?.ambiguous ?? true)
    }

    // Integration regression for issue #3: when a single-window app empties out, the real
    // WindowCountingService yields before = {count 1, not ambiguous} and after =
    // {count 0, ambiguous} ("No windows returned"). decideAfterCmdW must request a quit —
    // previously it bailed on the ambiguous flag, so Cmd+W never quit any app.
    func testCmdWDecisionQuitsWhenRealCountingServiceReportsAppEmptied() {
        let classifier = WindowClassifier()
        func count(_ windows: [WindowInfo]) -> WindowCountResult? {
            let ax = MockAXInspector()
            ax.windowInfosToReturn = windows
            return WindowCountingService(
                axInspector: ax,
                classifier: classifier,
                windowServerInspector: MockWindowServerInspector()
            ).countWindows(for: 1, appIsHidden: false, settings: .default)
        }

        let normalWindow = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false,
            isVisible: true,
            title: "Doc"
        )
        let before = count([normalWindow])
        let after = count([])

        XCTAssertEqual(before?.count, 1)
        XCTAssertEqual(before?.ambiguous, false)
        XCTAssertEqual(after?.count, 0)
        XCTAssertEqual(after?.ambiguous, true)

        let decision = DecisionEngine().decideAfterCmdW(
            isEnabled: true,
            isPaused: false,
            permissionGranted: true,
            resolvedPolicy: ResolvedPolicy(behavior: .smartClose, matchedRule: nil, isExcluded: false),
            windowsBefore: before,
            windowsAfter: after
        )
        XCTAssertEqual(decision.action, .requestQuit)
    }
}
