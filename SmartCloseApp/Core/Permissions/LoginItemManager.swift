import Foundation
import ServiceManagement

final class LoginItemManager {
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.settings.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
