import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class SettingsStore: ObservableObject {
    @Published private(set) var settings: Settings

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let settingsKey = "SmartClose.Settings"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? Self.makeDefaults()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let data = self.defaults.data(forKey: settingsKey),
           let decoded = try? decoder.decode(Settings.self, from: data) {
            self.settings = SettingsStore.normalize(settings: decoded)
            Log.settings.info("Loaded settings from defaults")
        } else {
            self.settings = Settings.default
            Log.settings.info("Using default settings (no saved settings)")
        }
    }

    func update(_ mutate: (inout Settings) -> Void) {
        var copy = settings
        mutate(&copy)
        set(copy)
    }

    func set(_ newSettings: Settings) {
        let normalized = SettingsStore.normalize(settings: newSettings)
        settings = normalized
        save(normalized)
    }

    func binding<T>(for keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { [weak self] in
                self?.settings[keyPath: keyPath] ?? Settings.default[keyPath: keyPath]
            },
            set: { [weak self] newValue in
                self?.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    @MainActor
    func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "Export SmartClose Settings"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SmartCloseSettings.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try encoder.encode(settings)
                try data.write(to: url, options: [.atomic])
            } catch {
                Log.settings.error("Failed to export settings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Import SmartClose Settings"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let imported = try decoder.decode(Settings.self, from: data)
                set(imported)
            } catch {
                Log.settings.error("Failed to import settings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func save(_ settings: Settings) {
        do {
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: settingsKey)
            Log.settings.info("Settings saved")
        } catch {
            Log.settings.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func normalize(settings: Settings) -> Settings {
        var normalized = settings
        if let pauseUntil = normalized.pauseUntil, pauseUntil <= Date() {
            normalized.pauseUntil = nil
        }
        if normalized.onboardingProgress.version != OnboardingProgress.currentVersion {
            normalized.onboardingProgress = .default
        }
        if normalized.firstRunCompleted {
            normalized.onboardingProgress.requestedRelaunch = false
        }
        return normalized
    }

    private static func makeDefaults() -> UserDefaults {
        let environment = ProcessInfo.processInfo.environment
        guard let suiteName = environment["SMARTCLOSE_TEST_USER_DEFAULTS_SUITE"] else {
            return .standard
        }

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
