import XCTest
@testable import SmartClose

final class OwnWindowHitTesterTests: XCTestCase {
    private let ownPID: pid_t = 100
    private let otherPID: pid_t = 200

    private func makeTester(_ windows: [OnScreenWindow]) -> OwnWindowHitTester {
        OwnWindowHitTester(ownPID: ownPID, windowListProvider: { windows })
    }

    func testPointInsideOwnWindowIsOwn() {
        let tester = makeTester([
            OnScreenWindow(ownerPID: ownPID, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        ])
        XCTAssertTrue(tester.isOwnWindow(at: CGPoint(x: 112, y: 110)))
    }

    func testPointInsideOtherAppWindowIsNotOwn() {
        let tester = makeTester([
            OnScreenWindow(ownerPID: otherPID, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        ])
        XCTAssertFalse(tester.isOwnWindow(at: CGPoint(x: 112, y: 110)))
    }

    func testPointOutsideOwnWindowIsNotOwn() {
        let tester = makeTester([
            OnScreenWindow(ownerPID: ownPID, bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
            OnScreenWindow(ownerPID: otherPID, bounds: CGRect(x: 600, y: 100, width: 400, height: 300))
        ])
        XCTAssertFalse(tester.isOwnWindow(at: CGPoint(x: 612, y: 110)))
    }

    func testOwnWindowBelowAnotherAppStillCountsAsOwn() {
        // Conservative by design: an overlay above our Settings window must not let an
        // Accessibility hit-test reach our own process from the event-tap thread.
        let tester = makeTester([
            OnScreenWindow(ownerPID: otherPID, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            OnScreenWindow(ownerPID: ownPID, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        ])
        XCTAssertTrue(tester.isOwnWindow(at: CGPoint(x: 112, y: 110)))
    }

    func testNoWindowsIsNotOwn() {
        XCTAssertFalse(makeTester([]).isOwnWindow(at: CGPoint(x: 10, y: 10)))
    }

    func testLiveWindowListIsReadableOffMainThread() {
        let expectation = expectation(description: "window list read on background thread")
        Thread {
            XCTAssertFalse(Thread.isMainThread)
            _ = OwnWindowHitTester.onScreenWindows()
            expectation.fulfill()
        }.start()
        wait(for: [expectation], timeout: 5)
    }
}
