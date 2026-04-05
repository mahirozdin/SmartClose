import AppKit
import Combine

@MainActor
final class StatusMenuController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let settingsStore: SettingsStore

    private let onOpenSettings: () -> Void
    private let onShowDiagnostics: () -> Void
    private let onQuit: () -> Void

    private var enabledItem: NSMenuItem!
    private var statusItemLabel: NSMenuItem!
    private var pauseItem: NSMenuItem!

    init(
        settingsStore: SettingsStore,
        onOpenSettings: @escaping () -> Void,
        onShowDiagnostics: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.onOpenSettings = onOpenSettings
        self.onShowDiagnostics = onShowDiagnostics
        self.onQuit = onQuit

        configureStatusItem()
        buildMenu()
        updateMenu(settings: settingsStore.settings)

        settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                self?.updateMenu(settings: settings)
            }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    private func configureStatusItem() {
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "SmartClose") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "SC"
            }
        }
        statusItem.menu = menu
    }

    private func buildMenu() {
        statusItemLabel = NSMenuItem(title: "Status: Unknown", action: nil, keyEquivalent: "")
        menu.addItem(statusItemLabel)

        enabledItem = NSMenuItem(title: "Enable SmartClose", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        pauseItem = NSMenuItem(title: "Pause for 1 hour", action: #selector(pauseForHour), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let diagnosticsItem = NSMenuItem(title: "Show Diagnostics", action: #selector(showDiagnostics), keyEquivalent: "d")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit SmartClose", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateMenu(settings: Settings) {
        let statusText = settings.isEnabled ? "Enabled" : "Disabled"
        statusItemLabel.title = "Status: \(statusText)"
        enabledItem.title = settings.isEnabled ? "Disable SmartClose" : "Enable SmartClose"

        if settings.isPaused {
            pauseItem.title = "Resume SmartClose"
        } else {
            pauseItem.title = "Pause for 1 hour"
        }

        statusItem.isVisible = settings.showMenuBarIcon
    }

    @objc private func toggleEnabled() {
        settingsStore.update { $0.isEnabled.toggle() }
    }

    @objc private func pauseForHour() {
        if settingsStore.settings.isPaused {
            settingsStore.update { $0.pauseUntil = nil }
        } else {
            settingsStore.update { $0.pauseUntil = Date().addingTimeInterval(60 * 60) }
        }
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func showDiagnostics() {
        onShowDiagnostics()
    }

    @objc private func quitApp() {
        onQuit()
    }
}
