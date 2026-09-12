import Foundation

/// Talks to Home Assistant's REST API with a long-lived access token.
/// Polling `/api/states` every few seconds is unglamorous but it survives
/// Wi-Fi drops and HA restarts without any reconnect logic to babysit.
@MainActor
final class HomeAssistantClient: ObservableObject {
    @Published private(set) var entities: [String: HAEntity] = [:]
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReachable = false

    private var baseURL: String = ""
    private var token: String = ""

    func configure(baseURL: String, token: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
    }

    var isConfigured: Bool { !baseURL.isEmpty && !token.isEmpty }

    func entity(_ id: String) -> HAEntity? { entities[id] }

    func refresh() async {
        guard isConfigured, let url = URL(string: "\(baseURL)/api/states") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: request(url: url, method: "GET"))
            guard let http = response as? HTTPURLResponse else { return }
            guard http.statusCode != 401 else {
                errorMessage = "Home Assistant rejected the token."
                isReachable = false
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                errorMessage = "Home Assistant returned \(http.statusCode)."
                isReachable = false
                return
            }
            let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            var parsed: [String: HAEntity] = [:]
            for item in raw {
                guard let entityID = item["entity_id"] as? String,
                      let state = item["state"] as? String else { continue }
                var attributes: [String: String] = [:]
                if let raw = item["attributes"] as? [String: Any] {
                    for (key, value) in raw {
                        attributes[key] = String(describing: value)
                    }
                }
                parsed[entityID] = HAEntity(entityID: entityID, state: state, attributes: attributes)
            }
            entities = parsed
            isReachable = true
            errorMessage = nil
        } catch {
            isReachable = false
            errorMessage = error.localizedDescription
        }
    }

    /// Flips the entity and refreshes, so the tile settles on HA's real state
    /// rather than an optimistic guess that may not have taken.
    func toggle(_ entity: HAEntity) async {
        let service: String
        switch entity.domain {
        case "scene": service = "turn_on"
        case "script", "automation": service = "turn_on"
        default: service = entity.isOn ? "turn_off" : "turn_on"
        }
        await callService(domain: entity.domain, service: service, entityID: entity.entityID)
    }

    func callService(domain: String, service: String, entityID: String) async {
        guard isConfigured,
              let url = URL(string: "\(baseURL)/api/services/\(domain)/\(service)") else { return }
        var req = request(url: url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["entity_id": entityID])
        _ = try? await URLSession.shared.data(for: req)
        await refresh()
    }

    private func request(url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 12
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    /// All entity IDs, for the picker in Settings.
    var sortedEntityIDs: [String] { entities.keys.sorted() }
}
