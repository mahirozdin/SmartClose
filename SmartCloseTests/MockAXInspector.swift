import AppKit
@testable import SmartClose

final class MockAXInspector: AXInspecting {
    var windowInfosToReturn: [WindowInfo] = []

    func elementAtScreenPoint(_ point: CGPoint) -> AXUIElement? { nil }
    func role(of element: AXUIElement) -> String? { nil }
    func subrole(of element: AXUIElement) -> String? { nil }
    func windowForElement(_ element: AXUIElement) -> AXUIElement? { nil }
    func pid(of element: AXUIElement) -> pid_t? { nil }
    func windowInfos(for pid: pid_t) -> [WindowInfo] { windowInfosToReturn }
}

final class MockWindowServerInspector: WindowServerInspecting {
    var onScreenWindowCountToReturn: Int?

    func onScreenWindowCount(for pid: pid_t) -> Int? {
        onScreenWindowCountToReturn
    }
}
