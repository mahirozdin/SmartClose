import AppKit
import ApplicationServices

protocol AXInspecting {
    func elementAtScreenPoint(_ point: CGPoint) -> AXUIElement?
    func role(of element: AXUIElement) -> String?
    func subrole(of element: AXUIElement) -> String?
    func windowForElement(_ element: AXUIElement) -> AXUIElement?
    func pid(of element: AXUIElement) -> pid_t?
    func windowInfos(for pid: pid_t) -> [WindowInfo]
}

final class AXInspector: AXInspecting {
    func elementAtScreenPoint(_ point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success else { return nil }
        return element
    }

    func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute)
    }

    func subrole(of element: AXUIElement) -> String? {
        attribute(element, kAXSubroleAttribute)
    }

    func windowForElement(_ element: AXUIElement) -> AXUIElement? {
        if let window: AXUIElement = attribute(element, kAXWindowAttribute) {
            return window
        }

        var current: AXUIElement? = element
        while let node = current {
            if let role: String = attribute(node, kAXRoleAttribute), role == kAXWindowRole as String {
                return node
            }
            current = attribute(node, kAXParentAttribute)
        }
        return nil
    }

    func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        return result == .success ? pid : nil
    }

    func windowInfos(for pid: pid_t) -> [WindowInfo] {
        let appElement = AXUIElementCreateApplication(pid)
        let windows: [AXUIElement] = attribute(appElement, kAXWindowsAttribute) ?? []
        return windows.map { window in
            WindowInfo(
                role: attribute(window, kAXRoleAttribute),
                subrole: attribute(window, kAXSubroleAttribute),
                isMinimized: attribute(window, kAXMinimizedAttribute),
                isVisible: attribute(window, AXAttribute.visible),
                title: attribute(window, kAXTitleAttribute)
            )
        }
    }

    private func attribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let unwrapped = value else { return nil }
        return unwrapped as? T
    }
}
