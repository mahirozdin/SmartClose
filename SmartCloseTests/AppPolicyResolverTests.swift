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
}
