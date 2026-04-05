import AppKit

enum AppRelauncher {
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        Log.app.info("Relaunching app via open -n \(bundlePath)")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        do {
            try task.run()
        } catch {
            Log.app.error("Failed to relaunch app: \(error.localizedDescription, privacy: .public)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}
