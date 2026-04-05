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
}
