import XCTest
@testable import SmartClose

final class SettingsCodableTests: XCTestCase {
    private func makeCoder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    func testDefaultsHaveCmdWDisabled() {
        let settings = Settings.default
        XCTAssertFalse(settings.enableCmdWHandling)
        XCTAssertEqual(settings.cmdWVerifyDelay, 0.25, accuracy: 0.0001)
        XCTAssertTrue(settings.cmdWPerApp.isEmpty)
    }

    func testRoundTripPreservesCmdWFields() throws {
        let (encoder, decoder) = makeCoder()
        var settings = Settings.default
        settings.enableCmdWHandling = true
        settings.cmdWVerifyDelay = 0.4
        settings.cmdWPerApp = ["com.example.app": false, "com.other.*": true]

        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(Settings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertTrue(decoded.enableCmdWHandling)
        XCTAssertEqual(decoded.cmdWVerifyDelay, 0.4, accuracy: 0.0001)
        XCTAssertEqual(decoded.cmdWPerApp["com.example.app"], false)
    }

    func testLegacySettingsWithoutCmdWKeysDecodeToDisabledDefaults() throws {
        // A settings blob saved by an older build that predates the Cmd+W keys.
        let legacyJSON = """
        {
          "isEnabled": true,
          "globalMode": "smartClose",
          "ignoredBundleIDs": ["com.apple.finder"],
          "useAllowList": false,
          "allowedBundleIDs": [],
          "perAppRules": {},
          "countMinimizedWindows": false,
          "countHiddenWindows": false,
          "diagnosticsEnabled": true,
          "launchAtLogin": false,
          "firstRunCompleted": true,
          "debugLoggingLevel": "info",
          "showMenuBarIcon": true,
          "onboardingProgress": {
            "version": 1,
            "lastStep": "allSet",
            "hasSeenQuickSetup": true,
            "requestedRelaunch": false
          }
        }
        """
        let (_, decoder) = makeCoder()
        let decoded = try decoder.decode(Settings.self, from: Data(legacyJSON.utf8))

        XCTAssertTrue(decoded.isEnabled)            // existing key still honored
        XCTAssertFalse(decoded.enableCmdWHandling)  // new keys fall back to safe defaults
        XCTAssertEqual(decoded.cmdWVerifyDelay, 0.25, accuracy: 0.0001)
        XCTAssertTrue(decoded.cmdWPerApp.isEmpty)
    }
}
