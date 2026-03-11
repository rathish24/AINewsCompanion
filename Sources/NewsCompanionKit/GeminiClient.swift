import Foundation

/// Gemini API client implementing AICompleting. API key is provided at init (e.g. from config; never hardcode).
public final class GeminiClient: AICompleting, Sendable {

    private let apiKey: String
    private let model: String
    private let timeout: TimeInterval

    public init(apiKey: String, model: String = "gemini-2.0-flash", timeout: TimeInterval = 60) {
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
    }

    public func complete(prompt: String) async throws -> String {
        // Per https://ai.google.dev/gemini-api/docs: v1beta, x-goog-api-key header.
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        print("[GeminiClient] request – model: \(model) promptLength: \(prompt.count)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = timeout
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 4096,
                "responseMimeType": "application/json"
            ] as [String : Any]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[GeminiClient] invalid response (not HTTPURLResponse)")
            throw AIClientError.invalidResponse
        }
        if http.statusCode != 200 {
            let msg = Self.parseAPIErrorBody(data, statusCode: http.statusCode)
            print("[GeminiClient] HTTP \(http.statusCode) – \(msg)")
            throw AIClientError.apiError(msg)
        }
        let content = try parseGeminiResponse(data)
        print("[GeminiClient] success – responseLength: \(content.count)")
        return content
    }

    /// Parses Google API error JSON: { "error": { "message": "...", "status": "..." } } or similar.
    private static func parseAPIErrorBody(_ data: Data, statusCode: Int) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Self.fallbackMessage(for: statusCode)
        }
        // Google API error shape
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        // Some APIs use "message" at top level
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return Self.fallbackMessage(for: statusCode)
    }

    private static func fallbackMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 400: return "Bad request. Check that the request format and parameters are valid."
        case 401: return "Invalid or missing API key. Check ApiKeys.xcconfig or your key in Google AI Studio."
        case 403: return "API key not allowed or Generative Language API not enabled. Enable the API and check key restrictions."
        case 404: return "Model or endpoint not found. The API may have been updated."
        case 429: return "Rate limit exceeded. Wait a moment and try again."
        case 500...599: return "Server error (\(statusCode)). Try again later."
        default: return "HTTP \(statusCode)"
        }
    }

    private func parseGeminiResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIClientError.invalidResponse
        }
        guard let candidates = json["candidates"] as? [[String: Any]], let first = candidates.first else {
            if let promptFeedback = json["promptFeedback"] as? [String: Any],
               let blockReason = promptFeedback["blockReason"] as? String {
                throw AIClientError.apiError("Content blocked: \(blockReason). Try a different article.")
            }
            throw AIClientError.invalidResponse
        }
        guard let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let part = parts.first,
              let text = part["text"] as? String else {
            let reason = (first["finishReason"] as? String).map { " (\($0))" } ?? ""
            throw AIClientError.apiError("No text in response\(reason). Try again or another article.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@available(*, deprecated, renamed: "AIClientError")
public typealias GeminiClientError = AIClientError
