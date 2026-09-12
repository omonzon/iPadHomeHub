import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, model }
    let id = UUID()
    let role: Role
    var text: String

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }
}

enum GeminiError: LocalizedError {
    case missingKey
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add a Gemini API key in Settings first."
        case .http(let code, let body):
            return "Gemini returned \(code). \(body)"
        case .emptyResponse:
            return "Gemini returned no text."
        }
    }
}

/// Thin wrapper over the Gemini generateContent endpoint.
///
/// The key lives in the Keychain on this one iPad. That is fine for a device
/// on your own wall; it is not fine for an app you hand to other people —
/// anyone with the device can read the key out, so scope it and set quotas.
struct GeminiClient {
    var apiKey: String
    var model: String

    func send(history: [ChatMessage], systemPrompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingKey }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: endpoint) else { throw GeminiError.emptyResponse }

        let contents: [[String: Any]] = history.map { message in
            ["role": message.role.rawValue,
             "parts": [["text": message.text]]]
        }

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1200
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data)
            throw GeminiError.http(http.statusCode, message)
        }

        guard let text = Self.extractText(from: data) else { throw GeminiError.emptyResponse }
        return text
    }

    private static func extractText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    private static func errorMessage(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return message
    }
}
