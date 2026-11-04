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
    /// Set when the decisive rule matched the faceless host app rather than the window
    /// owner itself (see `HostAppResolver`). Surfaced in diagnostics.
    var viaHostBundleID: String? = nil
}

/// Finds the faceless host app that embeds a windowed UI app.
///
/// Some apps ship their UI as a separate app bundle nested inside an agent (`LSUIElement`) or
/// background-only (`LSBackgroundOnly`) host. Docker Desktop is the canonical case: the user-facing
/// `Docker.app` (`com.docker.docker`) is a faceless agent, while every window belongs to
/// `Docker.app/Contents/MacOS/Docker Desktop.app` (`com.electron.dockerdesktop`). Users naturally
/// write rules for the host id, so the host is consulted as a fallback (issue #25).
///
/// Only a faceless host qualifies. A regular app that bundles other apps (Xcode with Simulator,
/// Instruments, …) is not a host: its rules must not leak onto those independent tools.
final class HostAppResolver: @unchecked Sendable {
    typealias InfoProvider = (URL) -> [String: Any]?

    private let infoProvider: InfoProvider
    private let lock = NSLock()
    private var cache: [String: String?] = [:]

    init(infoProvider: @escaping InfoProvider = { Bundle(url: $0)?.infoDictionary }) {
        self.infoProvider = infoProvider
    }

    /// Bundle id of the faceless app that encloses the app bundle at `bundleURL`, or nil when the
    /// app is not nested or its enclosing app is a regular app. Results are cached per bundle path,
    /// so the Info.plist is read at most once per app; safe to call from the event-tap thread.
    func hostBundleID(forAppAt bundleURL: URL?) -> String? {
        guard let bundleURL else { return nil }
        let key = bundleURL.standardizedFileURL.path

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = computeHostBundleID(forAppAt: bundleURL.standardizedFileURL)

        lock.lock()
        cache[key] = .some(result)
        lock.unlock()
        return result
    }

    /// Nearest ancestor directory with an `.app` extension, excluding `url` itself.
    static func enclosingAppURL(of url: URL) -> URL? {
        var current = url.standardizedFileURL.deletingLastPathComponent()
        while current.path != "/", !current.path.isEmpty {
            if current.pathExtension.lowercased() == "app" {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    static func isFaceless(info: [String: Any]) -> Bool {
        flag(info["LSUIElement"]) || flag(info["LSBackgroundOnly"])
    }

    private func computeHostBundleID(forAppAt url: URL) -> String? {
        guard let hostURL = Self.enclosingAppURL(of: url),
              let info = infoProvider(hostURL),
              let hostID = info["CFBundleIdentifier"] as? String,
              !hostID.isEmpty,
              Self.isFaceless(info: info) else {
            return nil
        }
        return hostID
    }

    private static func flag(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["1", "yes", "true"].contains(string.lowercased())
        default:
            return false
        }
    }
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

    /// Resolves the close-button policy for the app owning the clicked window.
    ///
    /// - Parameter hostBundleID: Faceless host app embedding the window owner, from
    ///   `HostAppResolver` (e.g. `com.docker.docker` for Docker Desktop's UI). Exclusions
    ///   (hard, allow list, ignore list) match either id, so the result can only fall back to
    ///   the system's normal close. Per-app rules prefer the window owner's own rule (exact,
    ///   then wildcard) and fall back to the host's.
    func resolve(bundleID: String, hostBundleID: String? = nil, settings: Settings) -> ResolvedPolicy {
        let host = Self.normalizedHost(hostBundleID, owner: bundleID)

        if matchesAny(patterns: hardExcludedBundleIDs, bundleID: bundleID) {
            return ResolvedPolicy(behavior: .disabled, matchedRule: String(localized: "Hard exclusion"), isExcluded: true)
        }
        if let host, matchesAny(patterns: hardExcludedBundleIDs, bundleID: host) {
            return ResolvedPolicy(behavior: .disabled, matchedRule: String(localized: "Hard exclusion"), isExcluded: true, viaHostBundleID: host)
        }

        if settings.useAllowList {
            let ownerAllowed = matchesAny(patterns: settings.allowedBundleIDs, bundleID: bundleID)
            let hostAllowed = host.map { matchesAny(patterns: settings.allowedBundleIDs, bundleID: $0) } ?? false
            if !ownerAllowed && !hostAllowed {
                return ResolvedPolicy(behavior: .disabled, matchedRule: String(localized: "Allow list"), isExcluded: true)
            }
        }

        if matchesAny(patterns: settings.ignoredBundleIDs, bundleID: bundleID) {
            return ResolvedPolicy(behavior: .disabled, matchedRule: String(localized: "Ignored bundle"), isExcluded: true)
        }
        if let host, matchesAny(patterns: settings.ignoredBundleIDs, bundleID: host) {
            return ResolvedPolicy(behavior: .disabled, matchedRule: String(localized: "Ignored bundle"), isExcluded: true, viaHostBundleID: host)
        }

        if let rule = Self.bestRule(in: settings.perAppRules, for: bundleID) {
            return resolve(policy: rule.value, global: settings.globalMode, matchedRule: rule.pattern)
        }
        if let host, let rule = Self.bestRule(in: settings.perAppRules, for: host) {
            return resolve(policy: rule.value, global: settings.globalMode, matchedRule: rule.pattern, viaHostBundleID: host)
        }

        return resolve(policy: .default, global: settings.globalMode, matchedRule: nil)
    }

    private func resolve(
        policy: AppPolicy,
        global: GlobalMode,
        matchedRule: String?,
        viaHostBundleID: String? = nil
    ) -> ResolvedPolicy {
        switch policy {
        case .default:
            switch global {
            case .smartClose:
                return ResolvedPolicy(behavior: .smartClose, matchedRule: matchedRule, isExcluded: false, viaHostBundleID: viaHostBundleID)
            case .alwaysNormalClose:
                return ResolvedPolicy(behavior: .alwaysNormalClose, matchedRule: matchedRule, isExcluded: false, viaHostBundleID: viaHostBundleID)
            }
        case .alwaysNormalClose:
            return ResolvedPolicy(behavior: .alwaysNormalClose, matchedRule: matchedRule, isExcluded: false, viaHostBundleID: viaHostBundleID)
        case .alwaysQuitOnLastWindow:
            return ResolvedPolicy(behavior: .smartClose, matchedRule: matchedRule, isExcluded: false, viaHostBundleID: viaHostBundleID)
        case .disabled:
            return ResolvedPolicy(behavior: .disabled, matchedRule: matchedRule, isExcluded: true, viaHostBundleID: viaHostBundleID)
        }
    }

    /// Exact key first, then the longest matching wildcard (ties broken alphabetically so the
    /// result does not depend on dictionary order).
    private static func bestRule<Value>(in rules: [String: Value], for bundleID: String) -> (pattern: String, value: Value)? {
        if let exact = rules[bundleID] {
            return (pattern: bundleID, value: exact)
        }
        let wildcard = rules
            .filter { WildcardMatcher.matches(pattern: $0.key, value: bundleID) }
            .sorted { $0.key.count != $1.key.count ? $0.key.count > $1.key.count : $0.key < $1.key }
            .first
        return wildcard.map { (pattern: $0.key, value: $0.value) }
    }

    private static func normalizedHost(_ host: String?, owner: String) -> String? {
        guard let host, !host.isEmpty, host != owner else { return nil }
        return host
    }

    /// Whether the optional Cmd+W handling should consider acting for this app.
    /// Returns false unless the global toggle is on, and always false for hard-excluded
    /// (incl. SmartClose itself), allow-list-rejected, or ignore-listed apps — checked against
    /// both the app and its faceless host, if any. A per-app `cmdWPerApp` override (exact, then
    /// longest wildcard; the app's own before the host's) wins; otherwise defaults to true.
    func cmdWEnabled(bundleID: String, hostBundleID: String? = nil, settings: Settings) -> Bool {
        guard settings.enableCmdWHandling else { return false }

        let host = Self.normalizedHost(hostBundleID, owner: bundleID)
        let ids = [bundleID] + (host.map { [$0] } ?? [])

        if ids.contains(where: { matchesAny(patterns: hardExcludedBundleIDs, bundleID: $0) }) {
            return false
        }
        if settings.useAllowList, !ids.contains(where: { matchesAny(patterns: settings.allowedBundleIDs, bundleID: $0) }) {
            return false
        }
        if ids.contains(where: { matchesAny(patterns: settings.ignoredBundleIDs, bundleID: $0) }) {
            return false
        }

        for id in ids {
            if let rule = Self.bestRule(in: settings.cmdWPerApp, for: id) {
                return rule.value
            }
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
