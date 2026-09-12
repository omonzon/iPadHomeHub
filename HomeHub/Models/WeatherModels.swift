import Foundation

struct WeatherSnapshot: Equatable {
    var temperature: Double
    var apparentTemperature: Double
    var humidity: Int
    var windSpeed: Double
    var code: Int
    var isDay: Bool
    var hourly: [HourForecast]
    var daily: [DayForecast]
    var fetchedAt: Date
}

struct HourForecast: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var temperature: Double
    var code: Int
}

struct DayForecast: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var high: Double
    var low: Double
    var code: Int
}

struct GeoResult: Identifiable, Equatable, Decodable {
    let id: Int
    let name: String
    let admin1: String?
    let country: String?
    let latitude: Double
    let longitude: Double

    var subtitle: String {
        [admin1, country].compactMap { $0 }.joined(separator: ", ")
    }
}

/// WMO weather interpretation codes, mapped to a label and an SF Symbol.
enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm, hail"
        default: return "—"
        }
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.min.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.sleet.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "questionmark"
        }
    }
}
