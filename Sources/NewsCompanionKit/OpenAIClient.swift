import Foundation

/// OpenAI Chat Completions API client conforming to AICompleting.
public final class OpenAIClient: AICompleting, Sendable {

    private let apiKey: String
    private let model: String
    private let timeout: TimeInterval

    public init(apiKey: String, model: String = "gpt-4o-mini", timeout: TimeInterval = 30) {
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
    }

    public func complete(prompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        print("[OpenAIClient] request – model: \(model) promptLength: \(prompt.count)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "max_tokens": 4096,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": "You are a precise news companion. Always respond with valid JSON only."],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[OpenAIClient] invalid response (not HTTPURLResponse)")
            throw AIClientError.invalidResponse
        }
        if http.statusCode != 200 {
            let msg = Self.parseError(data, statusCode: http.statusCode)
            print("[OpenAIClient] HTTP \(http.statusCode) – \(msg)")
            throw AIClientError.apiError(msg)
        }
        let content = try Self.parseResponse(data)
        print("[OpenAIClient] success – responseLength: \(content.count)")
        return content
    }

    private static func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIClientError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseError(_ data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        return "HTTP \(statusCode)"
    }
}
