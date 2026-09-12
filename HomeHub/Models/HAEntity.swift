import Foundation

struct HAEntity: Identifiable, Equatable {
    var id: String { entityID }
    let entityID: String
    let state: String
    let attributes: [String: String]

    var domain: String { entityID.split(separator: ".").first.map(String.init) ?? "" }

    var friendlyName: String {
        attributes["friendly_name"] ?? entityID
    }

    var isOn: Bool {
        state == "on" || state == "open" || state == "home" || state == "playing"
    }

    /// Domains this hub knows how to toggle with a tap.
    var isToggleable: Bool {
        ["light", "switch", "fan", "input_boolean", "automation", "script", "scene"].contains(domain)
    }

    var unit: String { attributes["unit_of_measurement"] ?? "" }

    var symbol: String {
        switch domain {
        case "light": return isOn ? "lightbulb.fill" : "lightbulb"
        case "switch", "input_boolean": return isOn ? "poweroutlet.type.b.fill" : "poweroutlet.type.b"
        case "fan": return "fanblades.fill"
        case "lock": return isOn ? "lock.open.fill" : "lock.fill"
        case "cover": return "blinds.horizontal.closed"
        case "climate": return "thermometer.medium"
        case "sensor", "binary_sensor": return "sensor.fill"
        case "media_player": return "hifispeaker.fill"
        case "scene": return "theatermasks.fill"
        case "script", "automation": return "bolt.fill"
        case "person", "device_tracker": return "person.fill"
        default: return "square.grid.2x2.fill"
        }
    }
}
