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
}
