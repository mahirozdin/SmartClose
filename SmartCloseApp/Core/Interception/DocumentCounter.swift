import AppKit
import CoreServices
import Foundation

/// Outcome of asking an app how many documents it has open.
enum DocumentCountResult: Equatable {
    case count(Int)
    /// The Apple Event failed with this `OSStatus` (permission denied, timeout, unsupported, …).
    case failed(OSStatus)

    /// `errAEEventNotPermitted`: the user denied SmartClose Automation access to the app.
    static let automationDenied: OSStatus = -1743
    /// `errAEEventWouldRequireUserConsent`.
    static let consentRequired: OSStatus = -1744

    /// Errors that will not go away by asking again a moment later: the user denied Automation
    /// access, the app is gone, or the app does not understand "count documents".
    var isPermanentFailure: Bool {
        guard case let .failed(code) = self else { return false }
        return [
            Self.automationDenied,
            Self.consentRequired,
            -600,   // procNotFound: the app quit.
            -609,   // connectionInvalid: the app quit while we were asking.
            -1708,  // errAEEventNotHandled: the app does not support the event.
            -1728   // errAENoSuchObject: the app has no "document" class.
        ].contains(code)
    }

    var summary: String {
        switch self {
        case let .count(count):
            return "documents \(count)"
        case let .failed(code):
            return "error \(code)"
        }
    }
}

protocol DocumentCounting {
    /// Synchronously asks the app for its open-document count. Blocks for up to `timeout`
    /// seconds, so never call it on the event-tap thread or the main thread.
    func documentCount(for pid: pid_t, timeout: TimeInterval) -> DocumentCountResult
}

/// Counts an app's open documents with the standard `count documents` Apple Event
/// (`core/cnte`, `kocl = docu`), exactly what `tell application id "…" to count documents` sends.
///
/// Used only for apps the user opts into with the "Quit when last document closes" per-app rule
/// (issues #29, #30). Adobe Illustrator and InDesign keep an empty application frame open as a
/// standard window after the last document closes, so Accessibility window counts cannot tell
/// "no documents" from "one document"; the app's own document count can.
final class AppleEventDocumentCounter: DocumentCounting {
    private static let countElementsClass = AEEventClass(kAECoreSuite)
    private static let countElementsID = AEEventID(kAECountElements)
    private static let documentClass = DescType(0x646F_6375) // 'docu'
    /// `kAEDoNotPromptForUserConsent`: never block on the Automation prompt here. Permission is
    /// requested when the rule is picked, or right after a check reports it missing.
    private static let doNotPromptForConsent = NSAppleEventDescriptor.SendOptions(rawValue: 0x0002_0000)

    func documentCount(for pid: pid_t, timeout: TimeInterval) -> DocumentCountResult {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: Self.countElementsClass,
            eventID: Self.countElementsID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(typeCode: Self.documentClass), forKeyword: AEKeyword(keyAEObjectClass))
        event.setParam(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyDirectObject))

        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, Self.doNotPromptForConsent], timeout: timeout)
        } catch let error as NSError {
            return .failed(OSStatus(truncatingIfNeeded: error.code))
        }
        return Self.parseCountReply(reply)
    }

    /// Reads the reply to `count documents`. Only a real integer counts: `int32Value` returns 0
    /// for anything it cannot read (missing value, text, a list), and 0 means "quit", so every
    /// other reply is a failure.
    static func parseCountReply(_ reply: NSAppleEventDescriptor) -> DocumentCountResult {
        if let errorDescriptor = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)) {
            let errorNumber = errorDescriptor.coerce(toDescriptorType: DescType(typeSInt32))?.int32Value ?? OSStatus(errAEEventFailed)
            if errorNumber != 0 {
                return .failed(errorNumber)
            }
        }
        guard
            let value = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)),
            Self.integerTypes.contains(value.descriptorType),
            let integer = value.coerce(toDescriptorType: DescType(typeSInt32)),
            integer.int32Value >= 0
        else {
            return .failed(OSStatus(errAECoercionFail))
        }
        return .count(Int(integer.int32Value))
    }

    private static let integerTypes: Set<DescType> = [
        DescType(typeSInt16), DescType(typeSInt32), DescType(typeSInt64),
        DescType(typeUInt16), DescType(typeUInt32), DescType(typeUInt64)
    ]
}

/// Latest document check per app. A newer close replaces an older check for the same app, so one
/// close produces one decision and one diagnostics entry. Thread-safe.
final class DocumentCheckTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [pid_t: UUID] = [:]

    /// Starts a check for `pid`, superseding any running one.
    func begin(pid: pid_t) -> UUID {
        let token = UUID()
        lock.lock()
        tokens[pid] = token
        lock.unlock()
        return token
    }

    func isCurrent(pid: pid_t, token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tokens[pid] == token
    }

    func finish(pid: pid_t, token: UUID) {
        lock.lock()
        if tokens[pid] == token {
            tokens.removeValue(forKey: pid)
        }
        lock.unlock()
    }

    /// Cancels every running check (monitoring stopped).
    func cancelAll() {
        lock.lock()
        tokens.removeAll()
        lock.unlock()
    }
}

/// Bounded polling schedule for the document check that follows a close in an app using the
/// "Quit when last document closes" rule. The app closes the document itself first (handling any
/// save prompt natively), so the check is retried for a few seconds.
struct DocumentVerificationPolicy: Equatable {
    let initialDelay: TimeInterval
    let retryInterval: TimeInterval
    let maxDuration: TimeInterval
    /// Apple Event reply timeout for each individual check.
    let requestTimeout: TimeInterval

    init(
        initialDelay: TimeInterval = 0.3,
        retryInterval: TimeInterval = 0.3,
        maxDuration: TimeInterval = 3.0,
        requestTimeout: TimeInterval = 1.0
    ) {
        self.initialDelay = max(0.05, initialDelay)
        self.retryInterval = max(0.05, retryInterval)
        self.maxDuration = max(self.initialDelay, maxDuration)
        self.requestTimeout = max(0.1, requestTimeout)
    }

    /// Delay before the next check, or nil to stop: the documents are gone (the caller quits),
    /// the failure is permanent, or the time budget is used up.
    func nextDelay(afterElapsed elapsed: TimeInterval, latestResult: DocumentCountResult?) -> TimeInterval? {
        if latestResult == .count(0) { return nil }
        if latestResult?.isPermanentFailure == true { return nil }
        guard elapsed < maxDuration else { return nil }
        return min(retryInterval, maxDuration - elapsed)
    }
}

/// Asks macOS for permission to send Apple Events to apps, so the Automation prompt appears when
/// the user picks the "Quit when last document closes" rule rather than at the first close.
enum AutomationPermission {
    private static let queue = DispatchQueue(label: "SmartClose.AutomationPermission", qos: .utility)

    /// Requests Automation access for every running regular app (one with a Dock icon) matching
    /// `pattern` (bundle id or wildcard). Background helpers never get a prompt. Apps that are not
    /// running are asked right after their first document check reports permission missing.
    static func requestForRunningApps(matching pattern: String) {
        let bundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard app.activationPolicy == .regular,
                  let id = app.bundleIdentifier,
                  WildcardMatcher.matches(pattern: pattern, value: id) else { return nil }
            return id
        })
        request(bundleIDs: bundleIDs)
    }

    /// Asks for Automation access to these apps on a background queue (the prompt blocks).
    static func request(bundleIDs: Set<String>) {
        guard !bundleIDs.isEmpty else { return }
        queue.async {
            for bundleID in bundleIDs {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                guard let aeDesc = target.aeDesc else { continue }
                let status = AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, true)
                Log.interception.info("Automation permission bundle=\(bundleID, privacy: .public) status=\(status)")
            }
        }
    }
}
