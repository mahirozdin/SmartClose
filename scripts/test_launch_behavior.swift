import AppKit

// Run outside the sandboxed XCUITest runner: Launch Services deliberately drops
// a sandboxed caller's launch environment, including our isolated test settings.
@main
struct LaunchBehaviorTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw Failure(description: "Usage: test-launch-behavior /path/to/SmartClose.app")
        }
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        guard FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Contents/MacOS/SmartClose").path) else {
            throw Failure(description: "SmartClose.app was not found at \(appURL.path)")
        }

        for showIcon in [false, true] {
            for login in [true, false] {
                try await check(appURL, showIcon: showIcon, login: login, setupCompleted: true)
            }
        }
        for login in [true, false] {
            try await check(appURL, showIcon: false, login: login, setupCompleted: false)
        }
        print("Passed all 6 launch/reopen scenarios.")
    }

    @MainActor
    static func check(_ appURL: URL, showIcon: Bool, login: Bool, setupCompleted: Bool) async throws {
        let label = "login=\(login), icon=\(showIcon), setupCompleted=\(setupCompleted)"
        let suite = "SmartCloseLaunchTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let settings = try JSONSerialization.data(withJSONObject: [
            "firstRunCompleted": setupCompleted,
            "showMenuBarIcon": showIcon,
            "launchAtLogin": false,
            "isEnabled": false
        ])
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.arguments = ["-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES"]
        configuration.environment = [
            "SMARTCLOSE_TEST_USER_DEFAULTS_SUITE": suite,
            "SMARTCLOSE_TEST_SETTINGS_JSON": String(decoding: settings, as: UTF8.self),
            "SMARTCLOSE_TEST_ACCESSIBILITY": "missing",
            "SMARTCLOSE_TEST_INPUT_MONITORING": "missing"
        ]
        if login {
            let event = NSAppleEventDescriptor(
                eventClass: kCoreEventClass,
                eventID: kAEOpenApplication,
                targetDescriptor: nil,
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
            configuration.appleEvent = event
        }

        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        defer { if !app.isTerminated { app.terminate() } }
        try await Task.sleep(for: .seconds(2))
        guard !app.isTerminated else { throw Failure(description: "App exited: \(label)") }
        let expectedWindows = login && setupCompleted ? 0 : 1
        guard visibleWindows(pid: app.processIdentifier) == expectedWindows else {
            throw Failure(description: "Expected \(expectedWindows) initial windows: \(label)")
        }
        guard app.activationPolicy == (setupCompleted ? .accessory : .regular) else {
            throw Failure(description: "Unexpected activation policy: \(label)")
        }

        // A later explicit open must reach the same process, including one that
        // started silently at login, and must not create duplicate windows.
        for _ in 0..<2 {
            let reopen = NSWorkspace.OpenConfiguration()
            reopen.allowsRunningApplicationSubstitution = false
            reopen.addsToRecentItems = false
            let reopened = try await NSWorkspace.shared.openApplication(at: appURL, configuration: reopen)
            guard reopened.processIdentifier == app.processIdentifier else {
                throw Failure(description: "Reopen started a different process: \(label)")
            }
            try await waitUntil("one window after reopen: \(label)") { visibleWindows(pid: app.processIdentifier) == 1 }
        }
        app.terminate()
        try await waitUntil("process termination: \(label)") { app.isTerminated }
        print("PASS \(label)")
    }

    static func visibleWindows(pid: pid_t) -> Int {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // Owner and layer are available without Screen Recording permission;
        // window titles are deliberately not inspected.
        return windows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) && ($0[kCGWindowLayer as String] as? Int) == 0
        }.count
    }

    @MainActor
    static func waitUntil(_ description: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw Failure(description: "Timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
