import ApplicationServices
import Foundation

final class WindowClassifier {
    private let normalSubroles: Set<String> = [
        kAXStandardWindowSubrole as String
    ]

    private let ignoredSubroles: Set<String> = [
        kAXDialogSubrole as String,
        kAXSystemDialogSubrole as String,
        kAXFloatingWindowSubrole as String,
        AXSubrole.popover,
        AXSubrole.sheet
    ]

    /// Whether a window with this role/subrole counts as a "normal" standard window for the
    /// last-window decision. Auxiliary windows — dialogs, the Find/Replace panel, floating
    /// inspectors, sheets, popovers — are not standard windows, so closing one must never quit
    /// the app (issue #6).
    func isStandardWindow(role: String?, subrole: String?) -> Bool {
        guard let role, role == kAXWindowRole as String else { return false }
        guard let subrole else { return false }
        return normalSubroles.contains(subrole)
    }

    func classify(windows: [WindowInfo], appIsHidden: Bool, settings: Settings) -> WindowCountResult {
        var countable = 0
        var ignored = 0
        var ambiguous = false
        var reasons: [String] = []
        var hasPotentiallyOpenAuxiliaryWindow = false

        for window in windows {
            guard let role = window.role else {
                ambiguous = true
                reasons.append("Missing role")
                continue
            }

            if role != kAXWindowRole as String {
                ignored += 1
                reasons.append("Ignored non-window role: \(role)")
                continue
            }

            guard let subrole = window.subrole else {
                ambiguous = true
                reasons.append("Missing subrole")
                continue
            }

            if ignoredSubroles.contains(subrole) {
                ignored += 1
                if window.isMinimized == true && !settings.countMinimizedWindows {
                    reasons.append("Ignored minimized auxiliary subrole: \(subrole)")
                } else {
                    hasPotentiallyOpenAuxiliaryWindow = true
                    reasons.append("Ignored auxiliary subrole: \(subrole)")
                }
                continue
            }

            if !normalSubroles.contains(subrole) {
                // Unknown subrole: be safe.
                ambiguous = true
                reasons.append("Unknown subrole: \(subrole)")
                continue
            }

            if appIsHidden && !settings.countHiddenWindows {
                ignored += 1
                reasons.append("Ignored because app is hidden")
                continue
            }

            if let isMinimized = window.isMinimized {
                if isMinimized && !settings.countMinimizedWindows {
                    ignored += 1
                    reasons.append("Ignored minimized window")
                    continue
                }
            } else if !settings.countMinimizedWindows {
                ambiguous = true
                reasons.append("Missing minimized state")
                continue
            }

            if let isVisible = window.isVisible {
                if !isVisible && !settings.countHiddenWindows {
                    ignored += 1
                    reasons.append("Ignored hidden window")
                    continue
                }
            } else if !settings.countHiddenWindows && window.isMinimized != false {
                ambiguous = true
                reasons.append("Missing visibility state")
                continue
            }

            countable += 1
        }

        // Some apps report a minimized standard window as an auxiliary window. When minimized
        // windows are counted, an auxiliary window alongside one standard window makes the
        // last-window decision unsafe. When the user explicitly ignores minimized windows, a
        // minimized auxiliary window remains ignored. With multiple standard windows, the
        // decision is already non-terminal and remains unambiguous.
        if countable == 1 && hasPotentiallyOpenAuxiliaryWindow {
            ambiguous = true
            reasons.append("Auxiliary window present alongside last standard window")
        }

        return WindowCountResult(count: countable, ambiguous: ambiguous, ignoredCount: ignored, reasons: reasons)
    }
}
