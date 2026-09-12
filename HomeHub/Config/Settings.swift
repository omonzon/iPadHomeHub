import Foundation
import Combine

struct HubSettings: Codable, Equatable {
    // Clock
    var use24HourClock: Bool = false
    var showSeconds: Bool = false

    // Weather (Open-Meteo — no account, no API key)
    var locationName: String = "Cupertino"
    var latitude: Double = 37.3230
    var longitude: Double = -122.0322
    var useFahrenheit: Bool = true

    // Calendar
    var calendarDaysAhead: Int = 7

    // Home Assistant
    var haBaseURL: String = ""              // e.g. http://homeassistant.local:8123
    var haEntityIDs: [String] = []          // entities pinned to the dashboard

    // Assistant
    var geminiModel: String = "gemini-2.5-flash"

    // Photos screensaver
    var photoAlbumName: String = ""         // empty = whole library
    var screensaverAfterMinutes: Int = 15   // 0 disables
    var photoIntervalSeconds: Int = 20

    static let `default` = HubSettings()
}

/// Only ever touched from views, i.e. the main thread.
final class SettingsStore: ObservableObject {
    @Published var settings: HubSettings {
        didSet { persist() }
    }

    /// Kept out of `HubSettings` on purpose — these go to the Keychain.
    @Published var haToken: String {
        didSet { Keychain.set(haToken, for: "ha_token") }
    }
    @Published var geminiAPIKey: String {
        didSet { Keychain.set(geminiAPIKey, for: "gemini_key") }
    }

    private let defaultsKey = "hub_settings_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: "hub_settings_v1"),
           let decoded = try? JSONDecoder().decode(HubSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
        haToken = Keychain.get("ha_token")
        geminiAPIKey = Keychain.get("gemini_key")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    var homeAssistantConfigured: Bool {
        !settings.haBaseURL.isEmpty && !haToken.isEmpty
    }

    var assistantConfigured: Bool { !geminiAPIKey.isEmpty }
}
