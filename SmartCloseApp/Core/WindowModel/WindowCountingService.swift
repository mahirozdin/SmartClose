import AppKit
import CoreGraphics

protocol WindowServerInspecting {
    func onScreenWindowCount(for pid: pid_t) -> Int?
}

final class QuartzWindowServerInspector: WindowServerInspecting {
    func onScreenWindowCount(for pid: pid_t) -> Int? {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let windowNumbers = infos.compactMap { info -> Int? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                return nil
            }

            let layer = info[kCGWindowLayer as String] as? Int ?? .max
            guard layer == 0 else { return nil }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { return nil }

            let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            guard width > 1, height > 1 else { return nil }

            return info[kCGWindowNumber as String] as? Int
        }

        let uniqueNumbers = Set(windowNumbers)
        return uniqueNumbers.isEmpty ? nil : uniqueNumbers.count
    }
}

final class WindowCountingService {
    private let axInspector: AXInspecting
    private let classifier: WindowClassifier
    private let windowServerInspector: WindowServerInspecting

    init(
        axInspector: AXInspecting,
        classifier: WindowClassifier,
        windowServerInspector: WindowServerInspecting = QuartzWindowServerInspector()
    ) {
        self.axInspector = axInspector
        self.classifier = classifier
        self.windowServerInspector = windowServerInspector
    }

    func countWindows(for pid: pid_t, appIsHidden: Bool, settings: Settings) -> WindowCountResult? {
        let windows = axInspector.windowInfos(for: pid)
        let axResult: WindowCountResult
        if windows.isEmpty {
            axResult = WindowCountResult(count: 0, ambiguous: true, ignoredCount: 0, reasons: ["No windows returned"])
        } else {
            axResult = classifier.classify(windows: windows, appIsHidden: appIsHidden, settings: settings)
        }

        guard
            axResult.ambiguous,
            !appIsHidden,
            !settings.countHiddenWindows,
            !settings.countMinimizedWindows,
            let fallbackCount = windowServerInspector.onScreenWindowCount(for: pid)
        else {
            return axResult
        }

        return WindowCountResult(
            count: fallbackCount,
            ambiguous: false,
            ignoredCount: axResult.ignoredCount,
            reasons: axResult.reasons + ["Used Quartz fallback count"]
        )
    }
}
