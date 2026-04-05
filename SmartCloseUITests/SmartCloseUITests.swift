import Foundation
import XCTest

final class SmartCloseUITests: XCTestCase {
    func testOnboardingBlocksUntilPermissionsGranted() {
        let app = launchApp(accessibility: "missing", inputMonitoring: "missing")

        XCTAssertTrue(app.staticTexts["SmartClose needs two permissions"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        XCTAssertFalse(app.staticTexts["Quick Setup"].exists)
    }

    func testOnboardingRemovesRefreshButtons() {
        let app = launchApp(accessibility: "missing", inputMonitoring: "missing")

        XCTAssertFalse(app.buttons["Refresh Status"].exists)
        XCTAssertTrue(app.buttons["Grant Access"].exists)
    }

    func testPermissionCallToActionsReflectState() {
        let app = launchApp(accessibility: "openSettings", inputMonitoring: "openSettings")

        XCTAssertTrue(app.staticTexts["SmartClose needs two permissions"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons.matching(identifier: "Open Settings").count, 2)
        XCTAssertFalse(app.buttons["Grant Access"].exists)
    }

    func testGrantedPermissionsResumeQuickSetup() {
        let app = launchApp(accessibility: "granted", inputMonitoring: "granted")

        XCTAssertTrue(app.staticTexts["Quick Setup"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.checkBoxes["Enable SmartClose"].exists)
    }

    private func launchApp(accessibility: String, inputMonitoring: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SMARTCLOSE_TEST_USER_DEFAULTS_SUITE"] = "SmartCloseUITests.\(UUID().uuidString)"
        app.launchEnvironment["SMARTCLOSE_TEST_ACCESSIBILITY"] = accessibility
        app.launchEnvironment["SMARTCLOSE_TEST_INPUT_MONITORING"] = inputMonitoring
        app.launch()
        return app
    }
}
