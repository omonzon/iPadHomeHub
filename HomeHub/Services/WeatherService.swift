import Foundation

/// Open-Meteo: free, no account, no API key. Good fit for a wall panel that
/// just needs a forecast and should keep working after you forget about it.
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private var lastRequest: (lat: Double, lon: Double, fahrenheit: Bool)?

    func refresh(latitude: Double, longitude: Double, fahrenheit: Bool) async {
        lastRequest = (latitude, longitude, fahrenheit)
        isLoading = true
        defer { isLoading = false }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh")
        ]

        guard let url = components.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Weather service returned an error."
                return
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            snapshot = decoded.toSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-run the last successful query — used by the periodic refresh timer.
    func refreshUsingLastRequest() async {
        guard let last = lastRequest else { return }
        await refresh(latitude: last.lat, longitude: last.lon, fahrenheit: last.fahrenheit)
    }

    // MARK: - Geocoding (for the location picker in Settings)

    static func search(city: String) async -> [GeoResult] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(GeocodeResponse.self, from: data) else { return [] }
        return decoded.results ?? []
    }
}

// MARK: - Wire format

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Double
        let weather_code: Int
        let is_day: Int
        let wind_speed_10m: Double
    }
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
    }
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily

    func toSnapshot() -> WeatherSnapshot {
        // Times come back in the location's own timezone with no offset,
        // so parse them as local wall-clock values.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let now = Date()
        var hours: [HourForecast] = []
        for (index, raw) in hourly.time.enumerated() {
            guard index < hourly.temperature_2m.count, index < hourly.weather_code.count,
                  let date = formatter.date(from: raw) else { continue }
            guard date >= now.addingTimeInterval(-3600) else { continue }
            hours.append(HourForecast(date: date,
                                      temperature: hourly.temperature_2m[index],
                                      code: hourly.weather_code[index]))
            if hours.count >= 12 { break }
        }

        var days: [DayForecast] = []
        for (index, raw) in daily.time.enumerated() {
            guard index < daily.temperature_2m_max.count,
                  index < daily.temperature_2m_min.count,
                  index < daily.weather_code.count,
                  let date = dayFormatter.date(from: raw) else { continue }
            days.append(DayForecast(date: date,
                                    high: daily.temperature_2m_max[index],
                                    low: daily.temperature_2m_min[index],
                                    code: daily.weather_code[index]))
        }

        return WeatherSnapshot(temperature: current.temperature_2m,
                               apparentTemperature: current.apparent_temperature,
                               humidity: Int(current.relative_humidity_2m.rounded()),
                               windSpeed: current.wind_speed_10m,
                               code: current.weather_code,
                               isDay: current.is_day == 1,
                               hourly: hours,
                               daily: days,
                               fetchedAt: Date())
    }
}

private struct GeocodeResponse: Decodable {
    let results: [GeoResult]?
}
