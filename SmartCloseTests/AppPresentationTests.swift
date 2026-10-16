import AppKit
import XCTest
@testable import SmartClose

final class AppPresentationTests: XCTestCase {
    func testLoginItemLaunchDoesNotPresentAWindowAfterSetup() {
        let event = makeEvent(property: keyAELaunchedAsLogInItem)
        let reason = AppLaunchReason(appleEvent: event)

        XCTAssertEqual(reason, .loginItem)
        XCTAssertEqual(AppPresentation.onLaunch(firstRunCompleted: true, reason: reason), .none)
    }

    func testNormalLaunchPresentsSettingsAfterSetup() {
        let reason = AppLaunchReason(appleEvent: makeEvent())

        XCTAssertEqual(reason, .normal)
        XCTAssertEqual(AppPresentation.onLaunch(firstRunCompleted: true, reason: reason), .settings)
    }

    func testLaunchWithoutAnAppleEventKeepsSettingsReachable() {
        let reason = AppLaunchReason(appleEvent: nil)

        XCTAssertEqual(reason, .normal)
        XCTAssertEqual(AppPresentation.onLaunch(firstRunCompleted: true, reason: reason), .settings)
    }

    func testOnlyAnOpenApplicationEventInTheCoreEventClassCountsAsALoginLaunch() {
        XCTAssertEqual(AppLaunchReason(appleEvent: makeEvent(eventID: kAEReopenApplication, property: keyAELaunchedAsLogInItem)), .normal)
        XCTAssertEqual(AppLaunchReason(appleEvent: makeEvent(eventClass: kAEInternetSuite, property: keyAELaunchedAsLogInItem)), .normal)
        XCTAssertEqual(AppLaunchReason(appleEvent: makeEvent(property: keyAELaunchedAsServiceItem)), .normal)
    }

    func testFirstRunPreservesOnboardingIncludingLoginLaunch() {
        for reason: AppLaunchReason in [.normal, .loginItem] {
            XCTAssertEqual(AppPresentation.onLaunch(firstRunCompleted: false, reason: reason), .onboarding)
        }
    }

    func testReopeningUsesSetupStateRatherThanTheOriginalLaunchReason() {
        // A process originally started at login must still respond to a later
        // explicit open request; the original launch reason is not sticky.
        XCTAssertEqual(AppPresentation.onUserRequest(firstRunCompleted: true), .settings)
        XCTAssertEqual(AppPresentation.onUserRequest(firstRunCompleted: false), .onboarding)
    }

    private func makeEvent(
        eventClass: AEEventClass = kCoreEventClass,
        eventID: AEEventID = kAEOpenApplication,
        property: AEKeyword? = nil
    ) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: eventClass,
            eventID: eventID,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let property {
            event.setParam(NSAppleEventDescriptor(enumCode: property), forKeyword: keyAEPropData)
        }
        return event
    }
}
