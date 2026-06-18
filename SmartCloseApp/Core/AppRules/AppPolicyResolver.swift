import Foundation

enum CloseBehavior: String {
    case smartClose
    case alwaysNormalClose
    case disabled
}

struct ResolvedPolicy {
    let behavior: CloseBehavior
    let matchedRule: String?
    let isExcluded: Bool
}

final class AppPolicyResolver {
    private let hardExcludedBundleIDs: [String]

    /// - Parameter selfBundleID: SmartClose's own bundle identifier. It is added to the
    ///   hard-exclusion list so closing SmartClose's own window can never quit the app.
    ///   Defaults to the running bundle id; injectable for tests.
    init(selfBundleID: String? = Bundle.main.bundleIdentifier) {
        var ids = [
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.systemuiserver"
        ]
        if let selfBundleID, !selfBundleID.isEmpty {
            ids.append(selfBundleID)
        }
        hardExcludedBundleIDs = ids
    }

    func resolve(bundleID: String, settings: Settings) -> ResolvedPolicy {
        if matchesAny(patterns: hardExcludedBundleIDs, bundleID: bundleID) {
            return ResolvedPolicy(behavior: .disabled, matchedRule: "Hard exclusion", isExcluded: true)
        }

        if settings.useAllowList {
            let isAllowed = matchesAny(patterns: settings.allowedBundleIDs, bundleID: bundleID)
            if !isAllowed {
                return ResolvedPolicy(behavior: .disabled, matchedRule: "Allow list", isExcluded: true)
            }
        }

        if matchesAny(patterns: settings.ignoredBundleIDs, bundleID: bundleID) {
            return ResolvedPolicy(behavior: .disabled, matchedRule: "Ignored bundle", isExcluded: true)
        }

        if let exactRule = settings.perAppRules[bundleID] {
            return resolve(policy: exactRule, global: settings.globalMode, matchedRule: bundleID)
        }

        let wildcardMatches = settings.perAppRules
            .filter { WildcardMatcher.matches(pattern: $0.key, value: bundleID) }
            .sorted { $0.key.count > $1.key.count }
        if let wildcardRule = wildcardMatches.first {
            return resolve(policy: wildcardRule.value, global: settings.globalMode, matchedRule: wildcardRule.key)
        }

        return resolve(policy: .default, global: settings.globalMode, matchedRule: nil)
    }

    private func resolve(policy: AppPolicy, global: GlobalMode, matchedRule: String?) -> ResolvedPolicy {
        switch policy {
        case .default:
            switch global {
            case .smartClose:
                return ResolvedPolicy(behavior: .smartClose, matchedRule: matchedRule, isExcluded: false)
            case .alwaysNormalClose:
                return ResolvedPolicy(behavior: .alwaysNormalClose, matchedRule: matchedRule, isExcluded: false)
            }
        case .alwaysNormalClose:
            return ResolvedPolicy(behavior: .alwaysNormalClose, matchedRule: matchedRule, isExcluded: false)
        case .alwaysQuitOnLastWindow:
            return ResolvedPolicy(behavior: .smartClose, matchedRule: matchedRule, isExcluded: false)
        case .disabled:
            return ResolvedPolicy(behavior: .disabled, matchedRule: matchedRule, isExcluded: true)
        }
    }

    /// Whether the optional Cmd+W handling should consider acting for this app.
    /// Returns false unless the global toggle is on, and always false for hard-excluded
    /// (incl. SmartClose itself), allow-list-rejected, or ignore-listed apps. A per-app
    /// `cmdWPerApp` override (exact, then longest wildcard) wins; otherwise defaults to true.
    func cmdWEnabled(bundleID: String, settings: Settings) -> Bool {
        guard settings.enableCmdWHandling else { return false }

        if matchesAny(patterns: hardExcludedBundleIDs, bundleID: bundleID) {
            return false
        }
        if settings.useAllowList, !matchesAny(patterns: settings.allowedBundleIDs, bundleID: bundleID) {
            return false
        }
        if matchesAny(patterns: settings.ignoredBundleIDs, bundleID: bundleID) {
            return false
        }

        if let exact = settings.cmdWPerApp[bundleID] {
            return exact
        }
        let wildcardMatches = settings.cmdWPerApp
            .filter { WildcardMatcher.matches(pattern: $0.key, value: bundleID) }
            .sorted { $0.key.count > $1.key.count }
        if let wildcard = wildcardMatches.first {
            return wildcard.value
        }
        return true
    }

    private func matchesAny(patterns: [String], bundleID: String) -> Bool {
        for pattern in patterns {
            if WildcardMatcher.matches(pattern: pattern, value: bundleID) {
                return true
            }
        }
        return false
    }
}
