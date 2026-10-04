import CoreGraphics
import Foundation

/// A window as reported by the WindowServer, reduced to what hit-testing needs.
struct OnScreenWindow: Equatable {
    let ownerPID: pid_t
    let bounds: CGRect
}

/// Answers "is this screen point over one of SmartClose's own windows?" using only the
/// WindowServer window list — never Accessibility or AppKit — so it is safe to call from the
/// event-tap thread.
///
/// This must run *before* any Accessibility hit-test. When `AXUIElementCopyElementAtPosition`
/// lands on our own process, AppKit answers the request in-process on the calling thread, which
/// makes SwiftUI evaluate its view graph off the main thread. macOS 27 enforces main-actor
/// isolation there and traps with `EXC_BREAKPOINT` (issue #20); older systems silently raced.
///
/// The check is deliberately conservative: any visible SmartClose window containing the point
/// counts, even if another app's window is stacked above it. The worst case is that a close
/// click on an overlapping window behaves like a normal close, which is far better than a crash.
struct OwnWindowHitTester {
    typealias WindowListProvider = () -> [OnScreenWindow]

    private let ownPID: pid_t
    private let windowListProvider: WindowListProvider

    init(
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        windowListProvider: @escaping WindowListProvider = OwnWindowHitTester.onScreenWindows
    ) {
        self.ownPID = ownPID
        self.windowListProvider = windowListProvider
    }

    func isOwnWindow(at point: CGPoint) -> Bool {
        windowListProvider().contains { window in
            window.ownerPID == ownPID && window.bounds.contains(point)
        }
    }

    /// On-screen windows from `CGWindowListCopyWindowInfo`. Owner PID and bounds are
    /// available without Screen Recording permission on every supported macOS version.
    static func onScreenWindows() -> [OnScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                return nil
            }
            return OnScreenWindow(ownerPID: pid, bounds: bounds)
        }
    }
}
