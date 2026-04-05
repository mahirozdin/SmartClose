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

    func classify(windows: [WindowInfo], appIsHidden: Bool, settings: Settings) -> WindowCountResult {
        var countable = 0
        var ignored = 0
        var ambiguous = false
        var reasons: [String] = []

        for window in windows {
            guard let role = window.role else {
                ambiguous = true
                reasons.append("Missing role")
                continue
            }

            if role != kAXWindowRole as String {
                ignored += 1
                continue
            }

            guard let subrole = window.subrole else {
                ambiguous = true
                reasons.append("Missing subrole")
                continue
            }

            if ignoredSubroles.contains(subrole) {
                ignored += 1
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
                continue
            }

            if let isMinimized = window.isMinimized {
                if isMinimized && !settings.countMinimizedWindows {
                    ignored += 1
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
                    continue
                }
            } else if !settings.countHiddenWindows && window.isMinimized != false {
                ambiguous = true
                reasons.append("Missing visibility state")
                continue
            }

            countable += 1
        }

        return WindowCountResult(count: countable, ambiguous: ambiguous, ignoredCount: ignored, reasons: reasons)
    }
}
