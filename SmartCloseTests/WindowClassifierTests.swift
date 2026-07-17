import XCTest
import ApplicationServices
@testable import SmartClose

final class WindowClassifierTests: XCTestCase {
    func testCountsNormalWindow() {
        let classifier = WindowClassifier()
        let window = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false,
            isVisible: true,
            title: "Main"
        )
        let settings = Settings.default
        let result = classifier.classify(windows: [window], appIsHidden: false, settings: settings)
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result.ambiguous)
    }

    func testIgnoresMinimizedWhenConfigured() {
        let classifier = WindowClassifier()
        let window = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: true,
            isVisible: true,
            title: "Main"
        )
        var settings = Settings.default
        settings.countMinimizedWindows = false
        let result = classifier.classify(windows: [window], appIsHidden: false, settings: settings)
        XCTAssertEqual(result.count, 0)
        XCTAssertFalse(result.ambiguous)
    }

    func testMissingVisibilityStillCountsVisibleStandardWindow() {
        let classifier = WindowClassifier()
        let window = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false,
            isVisible: nil,
            title: "Main"
        )
        let settings = Settings.default
        let result = classifier.classify(windows: [window], appIsHidden: false, settings: settings)
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result.ambiguous)
    }

    func testUnknownSubroleIsAmbiguous() {
        let classifier = WindowClassifier()
        let window = WindowInfo(
            role: kAXWindowRole as String,
            subrole: "AXUnknown",
            isMinimized: false,
            isVisible: true,
            title: "Main"
        )
        let settings = Settings.default
        let result = classifier.classify(windows: [window], appIsHidden: false, settings: settings)
        XCTAssertTrue(result.ambiguous)
    }

    func testAuxiliaryWindowAlongsideLastStandardWindowIsAmbiguous() {
        let classifier = WindowClassifier()
        let standardWindow = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false,
            isVisible: true,
            title: "Main"
        )
        let dialogWindow = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            isMinimized: true,
            isVisible: false,
            title: "Minimized window reported as dialog"
        )

        var settings = Settings.default
        settings.countMinimizedWindows = true
        settings.countHiddenWindows = true

        let result = classifier.classify(
            windows: [standardWindow, dialogWindow],
            appIsHidden: false,
            settings: settings
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.ignoredCount, 1)
        XCTAssertTrue(result.ambiguous)
        XCTAssertTrue(result.reasons.contains("Auxiliary window present alongside last standard window"))
    }

    func testMinimizedAuxiliaryWindowIsIgnoredWhenConfigured() {
        let classifier = WindowClassifier()
        let standardWindow = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false,
            isVisible: true,
            title: "Main"
        )
        let minimizedDialogWindow = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            isMinimized: true,
            isVisible: false,
            title: "Minimized window reported as dialog"
        )

        var settings = Settings.default
        settings.countMinimizedWindows = false

        let result = classifier.classify(
            windows: [standardWindow, minimizedDialogWindow],
            appIsHidden: false,
            settings: settings
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.ignoredCount, 1)
        XCTAssertFalse(result.ambiguous)
        XCTAssertTrue(result.reasons.contains("Ignored minimized auxiliary subrole: AXDialog"))
    }

    func testAuxiliaryWindowAlongsideMultipleStandardWindowsIsNotAmbiguous() {
        let classifier = WindowClassifier()
        let standardWindow = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false,
            isVisible: true,
            title: "Main"
        )
        let secondStandardWindow = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false,
            isVisible: true,
            title: "Second"
        )
        let dialogWindow = WindowInfo(
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            isMinimized: false,
            isVisible: true,
            title: "Dialog"
        )

        let result = classifier.classify(
            windows: [standardWindow, secondStandardWindow, dialogWindow],
            appIsHidden: false,
            settings: Settings.default
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.ignoredCount, 1)
        XCTAssertFalse(result.ambiguous)
    }

    // MARK: - isStandardWindow (issue #6: closing an auxiliary window must not quit)

    func testIsStandardWindowTrueForStandardWindow() {
        let classifier = WindowClassifier()
        XCTAssertTrue(classifier.isStandardWindow(role: kAXWindowRole as String, subrole: kAXStandardWindowSubrole as String))
    }

    func testIsStandardWindowFalseForAuxiliaryWindows() {
        let classifier = WindowClassifier()
        XCTAssertFalse(classifier.isStandardWindow(role: kAXWindowRole as String, subrole: kAXDialogSubrole as String))
        XCTAssertFalse(classifier.isStandardWindow(role: kAXWindowRole as String, subrole: kAXFloatingWindowSubrole as String))
        XCTAssertFalse(classifier.isStandardWindow(role: kAXWindowRole as String, subrole: kAXSystemDialogSubrole as String))
        XCTAssertFalse(classifier.isStandardWindow(role: kAXWindowRole as String, subrole: "AXUnknown"))
    }

    func testIsStandardWindowFalseForMissingOrNonWindowRole() {
        let classifier = WindowClassifier()
        XCTAssertFalse(classifier.isStandardWindow(role: nil, subrole: kAXStandardWindowSubrole as String))
        XCTAssertFalse(classifier.isStandardWindow(role: kAXWindowRole as String, subrole: nil))
        XCTAssertFalse(classifier.isStandardWindow(role: "AXButton", subrole: kAXStandardWindowSubrole as String))
    }
}
