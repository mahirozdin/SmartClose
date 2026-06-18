import XCTest
@testable import SmartClose

final class AppPolicyResolverTests: XCTestCase {
    func testGlobalModeDefault() {
        var settings = Settings.default
        settings.globalMode = .smartClose
        settings.ignoredBundleIDs = []
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: "com.example.app", settings: settings)
        XCTAssertEqual(resolved.behavior, .smartClose)
        XCTAssertFalse(resolved.isExcluded)
    }

    func testPerAppAlwaysNormalClose() {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.perAppRules = ["com.example.app": .alwaysNormalClose]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: "com.example.app", settings: settings)
        XCTAssertEqual(resolved.behavior, .alwaysNormalClose)
    }

    func testWildcardRule() {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.perAppRules = ["com.example.*": .alwaysQuitOnLastWindow]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: "com.example.tool", settings: settings)
        XCTAssertEqual(resolved.behavior, .smartClose)
    }

    func testAllowListExcludesUnknown() {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.useAllowList = true
        settings.allowedBundleIDs = ["com.example.allowed"]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: "com.example.other", settings: settings)
        XCTAssertTrue(resolved.isExcluded)
    }

    func testSelfBundleIsHardExcluded() {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.useAllowList = false
        let resolver = AppPolicyResolver(selfBundleID: "com.smartclose.app")

        let resolved = resolver.resolve(bundleID: "com.smartclose.app", settings: settings)
        XCTAssertTrue(resolved.isExcluded)
        XCTAssertEqual(resolved.behavior, .disabled)
        XCTAssertEqual(resolved.matchedRule, "Hard exclusion")
    }

    // MARK: - Cmd+W resolution

    func testCmdWDisabledByDefault() {
        var settings = Settings.default // enableCmdWHandling == false
        settings.ignoredBundleIDs = []
        let resolver = AppPolicyResolver()

        XCTAssertFalse(resolver.cmdWEnabled(bundleID: "com.example.app", settings: settings))
    }

    func testCmdWEnabledAppliesToUnlistedAppWhenGlobalOn() {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.enableCmdWHandling = true
        let resolver = AppPolicyResolver()

        XCTAssertTrue(resolver.cmdWEnabled(bundleID: "com.example.app", settings: settings))
    }

    func testCmdWPerAppOptOut() {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.enableCmdWHandling = true
        settings.cmdWPerApp = ["com.example.app": false]
        let resolver = AppPolicyResolver()

        XCTAssertFalse(resolver.cmdWEnabled(bundleID: "com.example.app", settings: settings))
    }

    func testCmdWPerAppWildcard() {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.enableCmdWHandling = true
        settings.cmdWPerApp = ["com.example.*": false]
        let resolver = AppPolicyResolver()

        XCTAssertFalse(resolver.cmdWEnabled(bundleID: "com.example.tool", settings: settings))
    }

    func testCmdWRespectsIgnoreList() {
        var settings = Settings.default
        settings.enableCmdWHandling = true
        settings.ignoredBundleIDs = ["com.example.app"]
        let resolver = AppPolicyResolver()

        XCTAssertFalse(resolver.cmdWEnabled(bundleID: "com.example.app", settings: settings))
    }

    func testCmdWNeverActsOnHardExcludedOrSelf() {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.enableCmdWHandling = true
        let resolver = AppPolicyResolver(selfBundleID: "com.smartclose.app")

        XCTAssertFalse(resolver.cmdWEnabled(bundleID: "com.apple.finder", settings: settings))
        XCTAssertFalse(resolver.cmdWEnabled(bundleID: "com.smartclose.app", settings: settings))
    }
}
