import Foundation

enum DecisionAction: String, Codable {
    case passThrough
    case requestQuit

    var displayName: String {
        switch self {
        case .passThrough:
            return String(localized: "Pass through")
        case .requestQuit:
            return String(localized: "Request quit")
        }
    }
}

struct DecisionContext {
    let isEnabled: Bool
    let isPaused: Bool
    let permissionGranted: Bool
    let resolvedPolicy: ResolvedPolicy
    let windowCount: WindowCountResult?
    /// Whether the window whose close button was clicked is itself a standard window.
    /// Closing an auxiliary panel (e.g. Find & Replace) must never quit the app.
    let closedWindowIsStandard: Bool
}

struct DecisionResult: Codable {
    let action: DecisionAction
    let reason: String
}

struct DecisionEngine {
    func decide(context: DecisionContext) -> DecisionResult {
        if !context.isEnabled {
            return DecisionResult(action: .passThrough, reason: String(localized: "SmartClose disabled"))
        }

        if context.isPaused {
            return DecisionResult(action: .passThrough, reason: String(localized: "Paused"))
        }

        if !context.permissionGranted {
            return DecisionResult(action: .passThrough, reason: String(localized: "Accessibility permission missing"))
        }

        if context.resolvedPolicy.isExcluded || context.resolvedPolicy.behavior == .disabled {
            return DecisionResult(action: .passThrough, reason: String(localized: "Excluded by policy"))
        }

        if context.resolvedPolicy.behavior == .alwaysNormalClose {
            return DecisionResult(action: .passThrough, reason: String(localized: "Always normal close policy"))
        }

        // Only the close button of a standard window can quit the app. Closing an auxiliary
        // window (Find & Replace, a dialog, a floating inspector, …) leaves the real windows
        // open, so it must pass through even if exactly one normal window exists (issue #6).
        if !context.closedWindowIsStandard {
            return DecisionResult(action: .passThrough, reason: String(localized: "Closed window is not a standard window"))
        }

        guard let windowCount = context.windowCount else {
            return DecisionResult(action: .passThrough, reason: String(localized: "Window count unavailable"))
        }

        if windowCount.ambiguous {
            return DecisionResult(action: .passThrough, reason: String(localized: "Ambiguous window classification"))
        }

        if windowCount.count == 1 {
            return DecisionResult(action: .requestQuit, reason: String(localized: "Last normal window"))
        }

        if windowCount.count == 0 {
            return DecisionResult(action: .passThrough, reason: String(localized: "No countable windows"))
        }

        return DecisionResult(action: .passThrough, reason: String(localized: "Multiple windows open"))
    }

    /// Decision for the optional Cmd+W path. Unlike `decide`, the keystroke is never
    /// swallowed: the app closes its own window first, then this is evaluated using the window
    /// count from *before* the keystroke and from *after*.
    ///
    /// We act only when there was at least one confidently-classified normal window **before**
    /// Cmd+W and the app reports zero windows **after**. Accepting a positive pre-close count is
    /// important for rapid multi-window sequences: Accessibility can briefly keep the previously
    /// closed window in its list, so the final Cmd+W may still observe a stale count greater than
    /// one (issue #10). The zero-window after-state remains the only quit trigger.
    ///
    /// Important: an app with no remaining windows reports `count == 0` but the window counter
    /// also flags that result `ambiguous` ("No windows returned"). So for the *after* state we
    /// trust the count, not the flag. (Trusting the flag was the bug behind issue #3 — the
    /// post-close 0-window state is always ambiguous, so a quit was never requested.) The
    /// `before` gate keeps us conservative: we only quit when we were sure there was one window.
    func decideAfterCmdW(
        isEnabled: Bool,
        isPaused: Bool,
        permissionGranted: Bool,
        resolvedPolicy: ResolvedPolicy,
        windowsBefore: WindowCountResult?,
        windowsAfter: WindowCountResult?
    ) -> DecisionResult {
        if !isEnabled {
            return DecisionResult(action: .passThrough, reason: String(localized: "SmartClose disabled"))
        }

        if isPaused {
            return DecisionResult(action: .passThrough, reason: String(localized: "Paused"))
        }

        if !permissionGranted {
            return DecisionResult(action: .passThrough, reason: String(localized: "Accessibility permission missing"))
        }

        if resolvedPolicy.isExcluded || resolvedPolicy.behavior == .disabled {
            return DecisionResult(action: .passThrough, reason: String(localized: "Excluded by policy"))
        }

        if resolvedPolicy.behavior == .alwaysNormalClose {
            return DecisionResult(action: .passThrough, reason: String(localized: "Always normal close policy"))
        }

        guard let before = windowsBefore, before.count > 0, !before.ambiguous else {
            return DecisionResult(action: .passThrough, reason: String(localized: "No confident normal window before Cmd+W"))
        }

        guard let after = windowsAfter else {
            return DecisionResult(action: .passThrough, reason: String(localized: "Window count unavailable"))
        }

        if after.count == 0 {
            return DecisionResult(action: .requestQuit, reason: String(localized: "Last window closed via Cmd+W"))
        }

        return DecisionResult(action: .passThrough, reason: String(localized: "Window still open after Cmd+W"))
    }
}
