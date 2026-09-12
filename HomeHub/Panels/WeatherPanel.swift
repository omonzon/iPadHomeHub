import SwiftUI

struct WeatherPanel: View {
    @ObservedObject var service: WeatherService
    let locationName: String
    let fahrenheit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: locationName,
                        systemImage: "location.fill",
                        trailing: service.snapshot.map { relative($0.fetchedAt) })

            if let snapshot = service.snapshot {
                current(snapshot)
                Divider().background(Theme.panelStroke)
                hourly(snapshot)
                Divider().background(Theme.panelStroke)
                daily(snapshot)
            } else if service.isLoading {
                PanelPlaceholder(message: "Loading forecast…")
            } else {
                PanelPlaceholder(message: service.errorMessage ?? "No forecast yet.")
            }
        }
        .panel()
    }

    private func current(_ snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: WeatherCode.symbol(snapshot.code, isDay: snapshot.isDay))
                .font(.system(size: 52))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Theme.warm)
                .frame(width: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(temp(snapshot.temperature))
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .foregroundColor(Theme.primaryText)
                Text(WeatherCode.description(snapshot.code))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                metric("thermometer.variable", "Feels \(temp(snapshot.apparentTemperature))")
                metric("humidity.fill", "\(snapshot.humidity)%")
                metric("wind", "\(Int(snapshot.windSpeed.rounded())) \(fahrenheit ? "mph" : "km/h")")
            }
        }
    }

    private func metric(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12))
            Text(text).font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(Theme.tertiaryText)
    }

    private func hourly(_ snapshot: WeatherSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(snapshot.hourly) { hour in
                    VStack(spacing: 8) {
                        Text(hourLabel(hour.date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.tertiaryText)
                        Image(systemName: WeatherCode.symbol(hour.code))
                            .font(.system(size: 17))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(Theme.accent)
                        Text(temp(hour.temperature))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.primaryText)
                    }
                }
            }
        }
    }

    private func daily(_ snapshot: WeatherSnapshot) -> some View {
        VStack(spacing: 10) {
            ForEach(snapshot.daily.prefix(5)) { day in
                HStack {
                    Text(dayLabel(day.date))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 90, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code))
                        .font(.system(size: 15))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(Theme.accent)
                        .frame(width: 28)
                    Spacer()
                    Text(temp(day.low))
                        .foregroundColor(Theme.tertiaryText)
                    Text(temp(day.high))
                        .foregroundColor(Theme.primaryText)
                        .frame(width: 56, alignment: .trailing)
                }
                .font(.system(size: 15, weight: .medium))
            }
        }
    }

    private func temp(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func relative(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        return minutes < 1 ? "just now" : "\(minutes)m ago"
    }
}
