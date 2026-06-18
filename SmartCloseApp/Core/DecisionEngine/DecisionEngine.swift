import Foundation

enum DecisionAction: String, Codable {
    case passThrough
    case requestQuit
}

struct DecisionContext {
    let isEnabled: Bool
    let isPaused: Bool
    let permissionGranted: Bool
    let resolvedPolicy: ResolvedPolicy
    let windowCount: WindowCountResult?
}

struct DecisionResult: Codable {
    let action: DecisionAction
    let reason: String
}

struct DecisionEngine {
    func decide(context: DecisionContext) -> DecisionResult {
        if !context.isEnabled {
            return DecisionResult(action: .passThrough, reason: "SmartClose disabled")
        }

        if context.isPaused {
            return DecisionResult(action: .passThrough, reason: "Paused")
        }

        if !context.permissionGranted {
            return DecisionResult(action: .passThrough, reason: "Accessibility permission missing")
        }

        if context.resolvedPolicy.isExcluded || context.resolvedPolicy.behavior == .disabled {
            return DecisionResult(action: .passThrough, reason: "Excluded by policy")
        }

        if context.resolvedPolicy.behavior == .alwaysNormalClose {
            return DecisionResult(action: .passThrough, reason: "Always normal close policy")
        }

        guard let windowCount = context.windowCount else {
            return DecisionResult(action: .passThrough, reason: "Window count unavailable")
        }

        if windowCount.ambiguous {
            return DecisionResult(action: .passThrough, reason: "Ambiguous window classification")
        }

        if windowCount.count == 1 {
            return DecisionResult(action: .requestQuit, reason: "Last normal window")
        }

        if windowCount.count == 0 {
            return DecisionResult(action: .passThrough, reason: "No countable windows")
        }

        return DecisionResult(action: .passThrough, reason: "Multiple windows open")
    }

    /// Decision for the optional Cmd+W path. Unlike `decide`, the keystroke is never
    /// swallowed: the app closes its own window first, then this is evaluated using the window
    /// count from *before* the keystroke and from *after*.
    ///
    /// We act only when there was exactly one confidently-classified normal window **before**
    /// Cmd+W (a plausible "last window"), and the app reports zero windows **after**.
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
            return DecisionResult(action: .passThrough, reason: "SmartClose disabled")
        }

        if isPaused {
            return DecisionResult(action: .passThrough, reason: "Paused")
        }

        if !permissionGranted {
            return DecisionResult(action: .passThrough, reason: "Accessibility permission missing")
        }

        if resolvedPolicy.isExcluded || resolvedPolicy.behavior == .disabled {
            return DecisionResult(action: .passThrough, reason: "Excluded by policy")
        }

        if resolvedPolicy.behavior == .alwaysNormalClose {
            return DecisionResult(action: .passThrough, reason: "Always normal close policy")
        }

        guard let before = windowsBefore, before.count == 1, !before.ambiguous else {
            return DecisionResult(action: .passThrough, reason: "Not a single normal window before Cmd+W")
        }

        guard let after = windowsAfter else {
            return DecisionResult(action: .passThrough, reason: "Window count unavailable")
        }

        if after.count == 0 {
            return DecisionResult(action: .requestQuit, reason: "Last window closed via Cmd+W")
        }

        return DecisionResult(action: .passThrough, reason: "Window still open after Cmd+W")
    }
}
