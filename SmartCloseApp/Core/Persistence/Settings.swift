import Foundation

enum GlobalMode: String, Codable, CaseIterable, Identifiable {
    case smartClose
    case alwaysNormalClose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smartClose: return "Smart close (quit on last window)"
        case .alwaysNormalClose: return "Always normal close"
        }
    }
}

enum AppPolicy: String, Codable, CaseIterable, Identifiable {
    case `default`
    case alwaysNormalClose
    case alwaysQuitOnLastWindow
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .alwaysNormalClose: return "Always normal close"
        case .alwaysQuitOnLastWindow: return "Always quit on last window"
        case .disabled: return "Disabled for this app"
        }
    }
}

enum DebugLoggingLevel: String, Codable, CaseIterable, Identifiable {
    case none
    case error
    case info
    case verbose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .error: return "Errors only"
        case .info: return "Info"
        case .verbose: return "Verbose"
        }
    }
}

struct OnboardingProgress: Codable, Equatable {
    enum Step: String, Codable {
        case permissions
        case quickSetup
        case allSet
    }

    static let currentVersion = 1

    var version: Int
    var lastStep: Step
    var hasSeenQuickSetup: Bool
    var requestedRelaunch: Bool

    static let `default` = OnboardingProgress(
        version: currentVersion,
        lastStep: .permissions,
        hasSeenQuickSetup: false,
        requestedRelaunch: false
    )

    static func resolvedStep(for settings: Settings, permissionsGranted: Bool) -> Step {
        guard !settings.firstRunCompleted else {
            return .allSet
        }
        guard permissionsGranted else {
            return .permissions
        }
        return settings.onboardingProgress.lastStep == .allSet ? .allSet : .quickSetup
    }
}

struct Settings: Codable, Equatable {
    var isEnabled: Bool
    var pauseUntil: Date?
    var globalMode: GlobalMode
    var ignoredBundleIDs: [String]
    var useAllowList: Bool
    var allowedBundleIDs: [String]
    var perAppRules: [String: AppPolicy]
    var countMinimizedWindows: Bool
    var countHiddenWindows: Bool
    var diagnosticsEnabled: Bool
    var launchAtLogin: Bool
    var firstRunCompleted: Bool
    var debugLoggingLevel: DebugLoggingLevel
    var showMenuBarIcon: Bool
    var onboardingProgress: OnboardingProgress

    static let defaultIgnoredBundleIDs: [String] = []

    static let `default` = Settings(
        isEnabled: false,
        pauseUntil: nil,
        globalMode: .smartClose,
        ignoredBundleIDs: Settings.defaultIgnoredBundleIDs,
        useAllowList: false,
        allowedBundleIDs: [],
        perAppRules: [:],
        countMinimizedWindows: false,
        countHiddenWindows: false,
        diagnosticsEnabled: true,
        launchAtLogin: false,
        firstRunCompleted: false,
        debugLoggingLevel: .info,
        showMenuBarIcon: true,
        onboardingProgress: .default
    )

    var isPaused: Bool {
        guard let pauseUntil else { return false }
        return pauseUntil > Date()
    }
}

extension Settings {
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case pauseUntil
        case globalMode
        case ignoredBundleIDs
        case useAllowList
        case allowedBundleIDs
        case perAppRules
        case countMinimizedWindows
        case countHiddenWindows
        case diagnosticsEnabled
        case launchAtLogin
        case firstRunCompleted
        case debugLoggingLevel
        case showMenuBarIcon
        case onboardingProgress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings.default

        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        pauseUntil = try container.decodeIfPresent(Date.self, forKey: .pauseUntil)
        globalMode = try container.decodeIfPresent(GlobalMode.self, forKey: .globalMode) ?? defaults.globalMode
        ignoredBundleIDs = try container.decodeIfPresent([String].self, forKey: .ignoredBundleIDs) ?? defaults.ignoredBundleIDs
        useAllowList = try container.decodeIfPresent(Bool.self, forKey: .useAllowList) ?? defaults.useAllowList
        allowedBundleIDs = try container.decodeIfPresent([String].self, forKey: .allowedBundleIDs) ?? defaults.allowedBundleIDs
        perAppRules = try container.decodeIfPresent([String: AppPolicy].self, forKey: .perAppRules) ?? defaults.perAppRules
        countMinimizedWindows = try container.decodeIfPresent(Bool.self, forKey: .countMinimizedWindows) ?? defaults.countMinimizedWindows
        countHiddenWindows = try container.decodeIfPresent(Bool.self, forKey: .countHiddenWindows) ?? defaults.countHiddenWindows
        diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? defaults.diagnosticsEnabled
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        firstRunCompleted = try container.decodeIfPresent(Bool.self, forKey: .firstRunCompleted) ?? defaults.firstRunCompleted
        debugLoggingLevel = try container.decodeIfPresent(DebugLoggingLevel.self, forKey: .debugLoggingLevel) ?? defaults.debugLoggingLevel
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? defaults.showMenuBarIcon
        onboardingProgress = try container.decodeIfPresent(OnboardingProgress.self, forKey: .onboardingProgress) ?? defaults.onboardingProgress
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(pauseUntil, forKey: .pauseUntil)
        try container.encode(globalMode, forKey: .globalMode)
        try container.encode(ignoredBundleIDs, forKey: .ignoredBundleIDs)
        try container.encode(useAllowList, forKey: .useAllowList)
        try container.encode(allowedBundleIDs, forKey: .allowedBundleIDs)
        try container.encode(perAppRules, forKey: .perAppRules)
        try container.encode(countMinimizedWindows, forKey: .countMinimizedWindows)
        try container.encode(countHiddenWindows, forKey: .countHiddenWindows)
        try container.encode(diagnosticsEnabled, forKey: .diagnosticsEnabled)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(firstRunCompleted, forKey: .firstRunCompleted)
        try container.encode(debugLoggingLevel, forKey: .debugLoggingLevel)
        try container.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try container.encode(onboardingProgress, forKey: .onboardingProgress)
    }
}
