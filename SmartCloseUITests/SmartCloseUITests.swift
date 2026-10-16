import AppKit
import XCTest

@MainActor
final class SmartCloseUITests: XCTestCase {
    func testManualLaunchAndReopenPresentSettingsWithEitherIconPreference() throws {
        for showMenuBarIcon in [false, true] {
            let app = try configuredApp(showMenuBarIcon: showMenuBarIcon)
            app.launch()
            defer { app.terminate() }

            let settings = app.windows["SmartClose Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertEqual((app.checkBoxes["Show menu bar icon"].value as? NSNumber)?.boolValue, showMenuBarIcon)
            settings.buttons[XCUIIdentifierCloseWindow].click()
            XCTAssertFalse(settings.exists)

            try openApp(app)
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertEqual(app.windows.matching(identifier: "SmartClose Settings").count, 1)
        }
    }

    func testReopenPreservesIncompleteOnboarding() throws {
        let app = try configuredApp(showMenuBarIcon: false, firstRunCompleted: false)
        app.launch()
        defer { app.terminate() }

        let onboarding = app.windows["Welcome to SmartClose"]
        XCTAssertTrue(onboarding.waitForExistence(timeout: 5))
        onboarding.buttons[XCUIIdentifierCloseWindow].click()

        try openApp(app)
        XCTAssertTrue(onboarding.waitForExistence(timeout: 5))
        XCTAssertFalse(app.windows["SmartClose Settings"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
    }

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

    func testRussianLocalizationRendersOnboarding() {
        let app = launchApp(accessibility: "missing", inputMonitoring: "missing", language: "ru")

        XCTAssertTrue(app.staticTexts["SmartClose нужны два разрешения"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons.matching(identifier: "Предоставить доступ").count, 2)
        XCTAssertTrue(app.buttons["Продолжить"].exists)
    }

    private func configuredApp(showMenuBarIcon: Bool, firstRunCompleted: Bool = true) throws -> XCUIApplication {
        let app = makeApp(accessibility: "missing", inputMonitoring: "missing")
        let data = try JSONSerialization.data(withJSONObject: [
            "firstRunCompleted": firstRunCompleted,
            "showMenuBarIcon": showMenuBarIcon,
            "launchAtLogin": false
        ])
        app.launchEnvironment["SMARTCLOSE_TEST_SETTINGS_JSON"] = try XCTUnwrap(String(data: data, encoding: .utf8))
        return app
    }

    private func openApp(_ app: XCUIApplication) throws {
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("SmartClose.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false

        let opened = expectation(description: "Launch Services opened SmartClose")
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { runningApp, error in
            XCTAssertNil(error)
            XCTAssertNotNil(runningApp)
            opened.fulfill()
        }
        wait(for: [opened], timeout: 10)
    }

    private func launchApp(accessibility: String, inputMonitoring: String, language: String? = nil) -> XCUIApplication {
        let app = makeApp(accessibility: accessibility, inputMonitoring: inputMonitoring)
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_RU"]
        }
        app.launch()
        return app
    }

    private func makeApp(accessibility: String, inputMonitoring: String) -> XCUIApplication {
        let app = XCUIApplication()
        let suiteName = "SmartCloseUITests.\(UUID().uuidString)"
        app.launchEnvironment["SMARTCLOSE_TEST_USER_DEFAULTS_SUITE"] = suiteName
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        app.launchEnvironment["SMARTCLOSE_TEST_ACCESSIBILITY"] = accessibility
        app.launchEnvironment["SMARTCLOSE_TEST_INPUT_MONITORING"] = inputMonitoring
        app.launchArguments = ["-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES"]
        return app
    }
}
