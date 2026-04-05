import AppKit
import Foundation

enum EventDisposition {
    case passThrough
    case swallow
}

enum EventMonitorError: Error, Equatable {
    case tapCreationFailed

    var message: String {
        switch self {
        case .tapCreationFailed:
            return "macOS did not allow SmartClose to create its global event tap."
        }
    }
}

final class EventMonitor {
    typealias Handler = (CGEvent) -> EventDisposition

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: Handler?
    private var monitorThread: Thread?
    private var monitorRunLoop: CFRunLoop?
    private var swallowNextMouseUp = false

    @discardableResult
    func start(handler: @escaping Handler) -> Result<Void, EventMonitorError> {
        stop()
        self.handler = handler
        Log.interception.info("Event monitor start requested")

        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<EventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleEvent(proxy: proxy, type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            Log.interception.error("Failed to create event tap (nil)")
            return .failure(.tapCreationFailed)
        }
        Log.interception.info("Event tap created")

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        monitorThread = Thread { [weak self] in
            guard let self, let runLoopSource = self.runLoopSource else { return }
            self.monitorRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            Log.interception.info("Event monitor run loop started")
            CFRunLoopRun()
        }
        monitorThread?.name = "SmartClose.EventMonitor"
        monitorThread?.start()
        return .success(())
    }

    func stop() {
        Log.interception.info("Event monitor stop requested")
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let runLoop = monitorRunLoop {
            CFRunLoopStop(runLoop)
        }
        if let thread = monitorThread {
            thread.cancel()
        }
        eventTap = nil
        runLoopSource = nil
        monitorThread = nil
        monitorRunLoop = nil
        handler = nil
        swallowNextMouseUp = false
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.interception.info("Event tap disabled by timeout/user input. Re-enabling.")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        if type == .leftMouseUp, swallowNextMouseUp {
            swallowNextMouseUp = false
            return nil
        }

        if type == .leftMouseDown {
            if handler?(event) == .swallow {
                swallowNextMouseUp = true
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }
}
