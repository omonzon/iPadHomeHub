import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.presentationMode) private var presentationMode

    @ObservedObject var weather: WeatherService
    @ObservedObject var homeAssistant: HomeAssistantClient

    @State private var citySearch = ""
    @State private var geoResults: [GeoResult] = []
    @State private var isSearching = false
    @State private var entityFilter = ""

    var body: some View {
        NavigationView {
            Form {
                clockSection
                weatherSection
                calendarSection
                homeAssistantSection
                assistantSection
                screensaverSection
                aboutSection
            }
            .navigationTitle("Hub Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var clockSection: some View {
        Section(header: Text("Clock")) {
            Toggle("24-hour time", isOn: binding(\.use24HourClock))
            Toggle("Show seconds", isOn: binding(\.showSeconds))
        }
    }

    private var weatherSection: some View {
        Section(header: Text("Weather"),
                footer: Text("Forecasts come from Open-Meteo. No account or API key needed.")) {
            HStack {
                Text("Location")
                Spacer()
                Text(settings.settings.locationName)
                    .foregroundColor(.secondary)
            }

            HStack {
                TextField("Search for a town or city", text: $citySearch)
                    .disableAutocorrection(true)
                Button("Search") { runSearch() }
                    .disabled(citySearch.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }

            if isSearching {
                HStack { ProgressView(); Text("Searching…").foregroundColor(.secondary) }
            }

            ForEach(geoResults) { result in
                Button {
                    apply(result)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                        Text(result.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Toggle("Fahrenheit", isOn: binding(\.useFahrenheit))
        }
    }

    private var calendarSection: some View {
        Section(header: Text("Calendar"),
                footer: Text("Reads the calendars already on this iPad. Grant access when prompted.")) {
            Stepper("Show \(settings.settings.calendarDaysAhead) days ahead",
                    value: binding(\.calendarDaysAhead), in: 1...30)
        }
    }

    private var homeAssistantSection: some View {
        Section(header: Text("Home Assistant"),
                footer: Text("Create a long-lived access token in Home Assistant under your profile › Security. Use the LAN address, e.g. http://homeassistant.local:8123")) {
            TextField("Base URL", text: binding(\.haBaseURL))
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            SecureField("Long-lived access token", text: $settings.haToken)

            Button("Test connection") {
                Task {
                    homeAssistant.configure(baseURL: settings.settings.haBaseURL, token: settings.haToken)
                    await homeAssistant.refresh()
                }
            }

            if let error = homeAssistant.errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            } else if homeAssistant.isReachable {
                Text("Connected — \(homeAssistant.entities.count) entities.")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if !homeAssistant.entities.isEmpty {
                NavigationLink(destination: entityPicker) {
                    Text("Pinned tiles (\(settings.settings.haEntityIDs.count))")
                }
            }
        }
    }

    private var entityPicker: some View {
        List {
            Section {
                TextField("Filter", text: $entityFilter)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            Section(header: Text("Entities")) {
                ForEach(filteredEntityIDs, id: \.self) { entityID in
                    Button {
                        togglePinned(entityID)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(homeAssistant.entity(entityID)?.friendlyName ?? entityID)
                                Text(entityID).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if settings.settings.haEntityIDs.contains(entityID) {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Pinned tiles")
    }

    private var assistantSection: some View {
        Section(header: Text("Assistant (Gemini)"),
                footer: Text("Get a key at aistudio.google.com. It is stored in this iPad's Keychain — anyone with the unlocked device can use it, so set a spending cap on the key.")) {
            SecureField("Gemini API key", text: $settings.geminiAPIKey)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            TextField("Model", text: binding(\.geminiModel))
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
    }

    private var screensaverSection: some View {
        Section(header: Text("Screensaver"),
                footer: Text("Leave the album name empty to use the whole photo library. Set the idle time to 0 to disable the screensaver.")) {
            TextField("Album name", text: binding(\.photoAlbumName))
            Stepper("Start after \(settings.settings.screensaverAfterMinutes) min",
                    value: binding(\.screensaverAfterMinutes), in: 0...120, step: 5)
            Stepper("Change photo every \(settings.settings.photoIntervalSeconds)s",
                    value: binding(\.photoIntervalSeconds), in: 5...300, step: 5)
        }
    }

    private var aboutSection: some View {
        Section(header: Text("About")) {
            HStack {
                Text("Version")
                Spacer()
                Text(versionString).foregroundColor(.secondary)
            }
            #if HOMEHUB_HOMEKIT
            Label("HomeKit enabled", systemImage: "checkmark.seal.fill")
                .foregroundColor(.green)
            #else
            Text("Built without HomeKit. Rebuild with the HOMEHUB_HOMEKIT flag and the HomeKit capability to enable it.")
                .font(.caption)
                .foregroundColor(.secondary)
            #endif
        }
    }

    // MARK: - Helpers

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var filteredEntityIDs: [String] {
        let query = entityFilter.trimmingCharacters(in: .whitespaces).lowercased()
        let all = homeAssistant.sortedEntityIDs
        guard !query.isEmpty else { return Array(all.prefix(300)) }
        return all.filter { id in
            id.lowercased().contains(query)
                || (homeAssistant.entity(id)?.friendlyName.lowercased().contains(query) ?? false)
        }
    }

    private func togglePinned(_ entityID: String) {
        if let index = settings.settings.haEntityIDs.firstIndex(of: entityID) {
            settings.settings.haEntityIDs.remove(at: index)
        } else {
            settings.settings.haEntityIDs.append(entityID)
        }
    }

    private func runSearch() {
        isSearching = true
        let query = citySearch
        Task {
            geoResults = await WeatherService.search(city: query)
            isSearching = false
        }
    }

    private func apply(_ result: GeoResult) {
        settings.settings.locationName = result.name
        settings.settings.latitude = result.latitude
        settings.settings.longitude = result.longitude
        geoResults = []
        citySearch = ""
        Task {
            await weather.refresh(latitude: result.latitude,
                                  longitude: result.longitude,
                                  fahrenheit: settings.settings.useFahrenheit)
        }
    }

    /// Two-way binding into the nested settings struct.
    private func binding<T>(_ keyPath: WritableKeyPath<HubSettings, T>) -> Binding<T> {
        Binding(
            get: { settings.settings[keyPath: keyPath] },
            set: { settings.settings[keyPath: keyPath] = $0 }
        )
    }
}
