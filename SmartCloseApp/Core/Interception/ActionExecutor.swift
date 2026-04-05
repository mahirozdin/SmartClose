import AppKit

final class ActionExecutor {
    func requestQuit(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            Log.interception.error("requestQuit failed: no app for pid \(pid)")
            return false
        }
        let result = app.terminate()
        Log.interception.info("requestQuit pid=\(pid) bundle=\(app.bundleIdentifier ?? "unknown") result=\(result)")
        return result
    }
}
