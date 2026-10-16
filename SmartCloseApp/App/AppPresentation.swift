import AppKit

enum AppLaunchReason: String {
    case loginItem
    case normal

    init(appleEvent: NSAppleEventDescriptor?) {
        // Read the event synchronously during applicationDidFinishLaunching, before
        // deferring any UI work. The login preference describes registration, not
        // the reason for this particular launch.
        if let appleEvent,
           appleEvent.eventClass == kCoreEventClass,
           appleEvent.eventID == kAEOpenApplication,
           appleEvent.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            self = .loginItem
        } else {
            self = .normal
        }
    }
}

enum AppPresentation: Equatable {
    case none
    case onboarding
    case settings

    static func onLaunch(firstRunCompleted: Bool, reason: AppLaunchReason) -> Self {
        guard firstRunCompleted else { return .onboarding }
        return reason == .loginItem ? .none : .settings
    }

    static func onUserRequest(firstRunCompleted: Bool) -> Self {
        firstRunCompleted ? .settings : .onboarding
    }
}
