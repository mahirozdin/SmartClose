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

    // MARK: - Faceless host apps (issue #25: Docker Desktop)

    private let dockerUI = "com.electron.dockerdesktop"
    private let dockerHost = "com.docker.docker"

    private func hostTestSettings() -> Settings {
        var settings = Settings.default
        settings.ignoredBundleIDs = []
        settings.globalMode = .smartClose
        return settings
    }

    func testIgnoringHostExcludesNestedUIApp() {
        var settings = hostTestSettings()
        settings.ignoredBundleIDs = [dockerHost]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings)
        XCTAssertTrue(resolved.isExcluded)
        XCTAssertEqual(resolved.behavior, .disabled)
        XCTAssertEqual(resolved.viaHostBundleID, dockerHost)
    }

    func testHostPerAppDisabledRuleAppliesToNestedUIApp() {
        var settings = hostTestSettings()
        settings.perAppRules = [dockerHost: .disabled]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings)
        XCTAssertTrue(resolved.isExcluded)
        XCTAssertEqual(resolved.matchedRule, dockerHost)
        XCTAssertEqual(resolved.viaHostBundleID, dockerHost)
    }

    func testHostRuleIsIgnoredWithoutHost() {
        // The pre-fix situation: no host known, so the host's rule cannot match.
        var settings = hostTestSettings()
        settings.perAppRules = [dockerHost: .disabled]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: dockerUI, settings: settings)
        XCTAssertFalse(resolved.isExcluded)
        XCTAssertEqual(resolved.behavior, .smartClose)
        XCTAssertNil(resolved.viaHostBundleID)
    }

    func testOwnPerAppRuleWinsOverHostRule() {
        var settings = hostTestSettings()
        settings.perAppRules = [dockerHost: .disabled, dockerUI: .alwaysNormalClose]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings)
        XCTAssertEqual(resolved.behavior, .alwaysNormalClose)
        XCTAssertEqual(resolved.matchedRule, dockerUI)
        XCTAssertNil(resolved.viaHostBundleID)
    }

    func testOwnWildcardRuleWinsOverHostExactRule() {
        var settings = hostTestSettings()
        settings.perAppRules = [dockerHost: .disabled, "com.electron.*": .alwaysQuitOnLastWindow]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings)
        XCTAssertEqual(resolved.behavior, .smartClose)
        XCTAssertEqual(resolved.matchedRule, "com.electron.*")
    }

    func testHostWildcardRuleApplies() {
        var settings = hostTestSettings()
        settings.perAppRules = ["com.docker.*": .disabled]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings)
        XCTAssertTrue(resolved.isExcluded)
        XCTAssertEqual(resolved.viaHostBundleID, dockerHost)
    }

    func testAllowListAcceptsHost() {
        var settings = hostTestSettings()
        settings.useAllowList = true
        settings.allowedBundleIDs = [dockerHost]
        let resolver = AppPolicyResolver()

        XCTAssertFalse(resolver.resolve(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings).isExcluded)
        XCTAssertTrue(resolver.resolve(bundleID: dockerUI, settings: settings).isExcluded)
    }

    func testHostEqualToOwnerIsIgnored() {
        var settings = hostTestSettings()
        settings.perAppRules = ["com.example.app": .alwaysNormalClose]
        let resolver = AppPolicyResolver()

        let resolved = resolver.resolve(bundleID: "com.example.app", hostBundleID: "com.example.app", settings: settings)
        XCTAssertEqual(resolved.behavior, .alwaysNormalClose)
        XCTAssertNil(resolved.viaHostBundleID)
    }

    func testCmdWHonorsHostIgnoreAndOverrides() {
        var settings = hostTestSettings()
        settings.enableCmdWHandling = true
        let resolver = AppPolicyResolver()

        settings.ignoredBundleIDs = [dockerHost]
        XCTAssertFalse(resolver.cmdWEnabled(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings))

        settings.ignoredBundleIDs = []
        settings.cmdWPerApp = [dockerHost: false]
        XCTAssertFalse(resolver.cmdWEnabled(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings))

        settings.cmdWPerApp = [dockerHost: false, dockerUI: true]
        XCTAssertTrue(resolver.cmdWEnabled(bundleID: dockerUI, hostBundleID: dockerHost, settings: settings))
    }

    // MARK: - HostAppResolver

    private static let dockerUIURL = URL(fileURLWithPath: "/Applications/Docker.app/Contents/MacOS/Docker Desktop.app")
    private static let simulatorURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")

    private static func plists(_ entries: [String: [String: Any]]) -> HostAppResolver.InfoProvider {
        { url in entries[url.standardizedFileURL.path] }
    }

    func testHostResolverFindsFacelessDockerHost() {
        let resolver = HostAppResolver(infoProvider: Self.plists([
            "/Applications/Docker.app": ["CFBundleIdentifier": "com.docker.docker", "LSUIElement": true]
        ]))
        XCTAssertEqual(resolver.hostBundleID(forAppAt: Self.dockerUIURL), "com.docker.docker")
    }

    func testHostResolverAcceptsBackgroundOnlyAndStringFlags() {
        let backgroundOnly = HostAppResolver(infoProvider: Self.plists([
            "/Applications/Docker.app": ["CFBundleIdentifier": "com.docker.docker", "LSBackgroundOnly": "1"]
        ]))
        XCTAssertEqual(backgroundOnly.hostBundleID(forAppAt: Self.dockerUIURL), "com.docker.docker")
    }

    func testHostResolverIgnoresRegularEnclosingApp() {
        // Xcode bundles Simulator, Instruments, … — independent apps that must not inherit Xcode's rules.
        let resolver = HostAppResolver(infoProvider: Self.plists([
            "/Applications/Xcode.app": ["CFBundleIdentifier": "com.apple.dt.Xcode"]
        ]))
        XCTAssertNil(resolver.hostBundleID(forAppAt: Self.simulatorURL))

        let explicitFalse = HostAppResolver(infoProvider: Self.plists([
            "/Applications/Docker.app": ["CFBundleIdentifier": "com.docker.docker", "LSUIElement": false]
        ]))
        XCTAssertNil(explicitFalse.hostBundleID(forAppAt: Self.dockerUIURL))
    }

    func testHostResolverReturnsNilForTopLevelOrMissingInput() {
        let resolver = HostAppResolver(infoProvider: { _ in XCTFail("No enclosing app to read"); return nil })
        XCTAssertNil(resolver.hostBundleID(forAppAt: URL(fileURLWithPath: "/Applications/Safari.app")))
        XCTAssertNil(resolver.hostBundleID(forAppAt: nil))
    }

    func testHostResolverCachesPerBundle() {
        var reads = 0
        let resolver = HostAppResolver(infoProvider: { _ in
            reads += 1
            return ["CFBundleIdentifier": "com.docker.docker", "LSUIElement": true]
        })
        XCTAssertEqual(resolver.hostBundleID(forAppAt: Self.dockerUIURL), "com.docker.docker")
        XCTAssertEqual(resolver.hostBundleID(forAppAt: Self.dockerUIURL), "com.docker.docker")
        XCTAssertEqual(reads, 1)
    }

    func testEnclosingAppURLSkipsSelf() {
        XCTAssertEqual(HostAppResolver.enclosingAppURL(of: Self.dockerUIURL)?.path, "/Applications/Docker.app")
        XCTAssertNil(HostAppResolver.enclosingAppURL(of: URL(fileURLWithPath: "/Applications/Docker.app")))
    }

    func testHostMatchDetailsNamesHost() {
        let viaHost = ResolvedPolicy(behavior: .disabled, matchedRule: dockerHost, isExcluded: true, viaHostBundleID: dockerHost)
        XCTAssertEqual(InterceptionController.hostMatchDetails(viaHost), "Rule matched host app com.docker.docker (com.docker.docker)")
        XCTAssertNil(InterceptionController.hostMatchDetails(ResolvedPolicy(behavior: .smartClose, matchedRule: nil, isExcluded: false)))
    }
}
