import SwiftUI
import Combine

@MainActor
struct RootView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var board: BoardStore

    @StateObject private var weather = WeatherService()
    @StateObject private var calendar = CalendarService()
    @StateObject private var homeAssistant = HomeAssistantClient()
    @StateObject private var photos = PhotoService()

    #if HOMEHUB_HOMEKIT
    @StateObject private var homeKit = HomeKitService()
    #endif

    @State private var showSettings = false
    @State private var showAssistant = false
    @State private var screensaverActive = false
    @State private var lastInteraction = Date()

    @State private var lastCalendarLoad = Date.distantPast

    /// One heartbeat drives everything: HA polling, the weather and calendar
    /// refresh intervals, repeating-chore resets and the idle timer.
    /// Static so re-rendering the view doesn't spawn a new timer each pass.
    private static let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            dashboard
                .opacity(screensaverActive ? 0 : 1)

            if screensaverActive {
                ScreensaverView(photos: photos,
                                use24Hour: settings.settings.use24HourClock,
                                intervalSeconds: settings.settings.photoIntervalSeconds,
                                onDismiss: wake)
                    .transition(.opacity)
            }
        }
        .statusBar(hidden: true)
        .simultaneousGesture(TapGesture().onEnded { lastInteraction = Date() })
        .sheet(isPresented: $showSettings) {
            SettingsView(weather: weather, homeAssistant: homeAssistant)
                .environmentObject(settings)
        }
        .fullScreenCover(isPresented: $showAssistant) {
            AssistantView(contextSummary: contextSummary)
                .environmentObject(settings)
                .environmentObject(board)
        }
        .task { await startUp() }
        .onReceive(Self.tick) { _ in heartbeat() }
        .onChange(of: showSettings) { isOpen in
            lastInteraction = Date()
            if !isOpen { Task { await applySettings() } }
        }
        .onChange(of: showAssistant) { _ in lastInteraction = Date() }
    }

    // MARK: - Layout

    /// Layout is chosen by width, not by device: a 12.9" in portrait and a
    /// 10.2" in landscape are the same problem. Three columns need real estate;
    /// below that, fold the grid rather than shrink everything.
    private enum LayoutMode {
        case wide       // 12.9"/11" landscape — three columns
        case medium     // 12.9" portrait, 9.7"/10.2" landscape — two columns
        case compact    // smaller iPads in portrait — one column

        init(width: CGFloat) {
            if width >= 1150 {
                self = .wide
            } else if width >= 800 {
                self = .medium
            } else {
                self = .compact
            }
        }
    }

    private var dashboard: some View {
        VStack(spacing: 16) {
            toolbar
            GeometryReader { geometry in
                layout(for: geometry)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func layout(for geometry: GeometryProxy) -> some View {
        switch LayoutMode(width: geometry.size.width) {
        case .wide:    wideLayout(geometry)
        case .medium:  mediumLayout()
        case .compact: compactLayout()
        }
    }

    /// Everything fits the viewport; only panels that manage their own
    /// overflow scroll.
    private func wideLayout(_ geometry: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                clockPanel
                weatherPanel
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width * 0.31)

            VStack(spacing: 16) {
                calendarPanel.frame(maxHeight: geometry.size.height * 0.55)
                notesPanel
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width * 0.34)

            VStack(spacing: 16) {
                homeControls.frame(maxHeight: geometry.size.height * 0.55)
                choresPanel
                Spacer(minLength: 0)
            }
        }
    }

    /// Two columns that scroll as a page. The panels that scroll internally get
    /// explicit heights so they stay bounded inside the outer scroll view.
    private func mediumLayout() -> some View {
        ScrollView(showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    clockPanel
                    weatherPanel
                    choresPanel.frame(height: 300)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    calendarPanel.frame(height: 340)
                    homeControls.frame(height: 300)
                    notesPanel.frame(height: 260)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// One column, everything stacked. Clock and weather keep their natural
    /// height so the top of the screen still reads at a glance from across
    /// the room.
    private func compactLayout() -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                clockPanel
                weatherPanel
                calendarPanel.frame(height: 320)
                homeControls.frame(height: 300)
                choresPanel.frame(height: 280)
                notesPanel.frame(height: 260)
            }
        }
    }

    // MARK: - Panels

    private var clockPanel: some View {
        ClockPanel(use24Hour: settings.settings.use24HourClock,
                   showSeconds: settings.settings.showSeconds)
    }

    private var weatherPanel: some View {
        WeatherPanel(service: weather,
                     locationName: settings.settings.locationName,
                     fahrenheit: settings.settings.useFahrenheit)
    }

    private var calendarPanel: some View { CalendarPanel(service: calendar) }
    private var choresPanel: some View { ChoresPanel() }
    private var notesPanel: some View { NotesPanel() }

    @ViewBuilder
    private var homeControls: some View {
        #if HOMEHUB_HOMEKIT
        HomeControlsPanel(homeAssistant: homeAssistant,
                          pinnedEntityIDs: settings.settings.haEntityIDs,
                          isConfigured: settings.homeAssistantConfigured,
                          homeKit: homeKit)
        #else
        HomeControlsPanel(homeAssistant: homeAssistant,
                          pinnedEntityIDs: settings.settings.haEntityIDs,
                          isConfigured: settings.homeAssistantConfigured)
        #endif
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Text(greeting)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Theme.primaryText)

            Spacer()

            toolbarButton("sparkles", tint: Theme.warm) { showAssistant = true }
            toolbarButton("photo.on.rectangle") { Task { await enterScreensaver() } }
            toolbarButton("arrow.clockwise") { Task { await refreshAll() } }
            toolbarButton("gearshape.fill") { showSettings = true }
        }
    }

    private func toolbarButton(_ symbol: String,
                               tint: Color = Theme.secondaryText,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<22: return "Good evening"
        default: return "Good night"
        }
    }

    // MARK: - Lifecycle

    private func startUp() async {
        await applySettings()
        await calendar.requestAccessAndLoad(daysAhead: settings.settings.calendarDaysAhead)
        #if HOMEHUB_HOMEKIT
        homeKit.start()
        #endif
    }

    private func applySettings() async {
        homeAssistant.configure(baseURL: settings.settings.haBaseURL, token: settings.haToken)
        await refreshAll()
    }

    private func refreshAll() async {
        lastInteraction = Date()
        await weather.refresh(latitude: settings.settings.latitude,
                              longitude: settings.settings.longitude,
                              fahrenheit: settings.settings.useFahrenheit)
        await homeAssistant.refresh()
        calendar.load(daysAhead: settings.settings.calendarDaysAhead)
        lastCalendarLoad = Date()
    }

    private func heartbeat() {
        board.resetRepeatingChores()

        let now = Date()

        // Home Assistant on every beat; weather every 10 minutes.
        Task {
            await homeAssistant.refresh()
            if let snapshot = weather.snapshot {
                if now.timeIntervalSince(snapshot.fetchedAt) > 600 {
                    await weather.refreshUsingLastRequest()
                }
            } else {
                await weather.refresh(latitude: settings.settings.latitude,
                                      longitude: settings.settings.longitude,
                                      fahrenheit: settings.settings.useFahrenheit)
            }
        }

        // Calendar every 5 minutes — EventKit reads are cheap but not free.
        if now.timeIntervalSince(lastCalendarLoad) > 300 {
            calendar.load(daysAhead: settings.settings.calendarDaysAhead)
            lastCalendarLoad = now
        }

        guard settings.settings.screensaverAfterMinutes > 0,
              !screensaverActive, !showSettings, !showAssistant else { return }

        let idleLimit = TimeInterval(settings.settings.screensaverAfterMinutes * 60)
        if now.timeIntervalSince(lastInteraction) > idleLimit {
            Task { await enterScreensaver() }
        }
    }

    private func enterScreensaver() async {
        await photos.prepare(albumName: settings.settings.photoAlbumName)
        withAnimation(.easeInOut(duration: 0.6)) { screensaverActive = true }
    }

    private func wake() {
        lastInteraction = Date()
        withAnimation(.easeInOut(duration: 0.4)) { screensaverActive = false }
        Task { await refreshAll() }
    }

    // MARK: - Assistant context

    private var contextSummary: String {
        var lines: [String] = []
        lines.append("Time: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short))")

        if let snapshot = weather.snapshot {
            let unit = settings.settings.useFahrenheit ? "F" : "C"
            lines.append("Weather in \(settings.settings.locationName): \(Int(snapshot.temperature.rounded()))°\(unit), \(WeatherCode.description(snapshot.code)), humidity \(snapshot.humidity)%.")
            if let today = snapshot.daily.first {
                lines.append("Today's range: \(Int(today.low.rounded()))° to \(Int(today.high.rounded()))°\(unit).")
            }
        }

        let upcoming = calendar.events.prefix(6).map { event -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE HH:mm"
            return event.isAllDay
                ? "\(event.title) (all day)"
                : "\(formatter.string(from: event.start)) \(event.title)"
        }
        if !upcoming.isEmpty {
            lines.append("Next events: " + upcoming.joined(separator: "; "))
        }

        return lines.joined(separator: "\n")
    }
}
