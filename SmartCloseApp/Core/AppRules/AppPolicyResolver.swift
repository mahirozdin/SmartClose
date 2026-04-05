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
    private let hardExcludedBundleIDs: [String] = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver"
    ]

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

    private func matchesAny(patterns: [String], bundleID: String) -> Bool {
        for pattern in patterns {
            if WildcardMatcher.matches(pattern: pattern, value: bundleID) {
                return true
            }
        }
        return false
    }
}
