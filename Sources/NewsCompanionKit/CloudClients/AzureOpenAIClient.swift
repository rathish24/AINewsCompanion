import Foundation

/// Azure OpenAI client for article-to-summary. Use your Azure OpenAI resource endpoint and deployment (model) name.
/// Conforms to `AICompleting`; pass the deployment name as the model you have available on your Azure server.
/// The prompt is built by ConversationEngine from conversation.json; response validation uses topics.json (same as Groq/OpenAI).
/// API key can be empty for local validation; requests will fail at runtime until you provide a valid key.
public final class AzureOpenAIClient: AICompleting, Sendable {

    private let endpoint: String
    private let deployment: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let apiVersion: String
    private let additionalHeaders: [String: String]?

    /// - Parameters:
    ///   - endpoint: Base URL of your Azure OpenAI resource (e.g. `https://your-resource.openai.azure.com`).
    ///   - deployment: Deployment name (model) on your server (e.g. `gpt-4o-mini` or your custom deployment name).
    ///   - apiKey: Azure OpenAI API key. Pass empty string to only validate client creation; add key when ready.
    ///   - timeout: Request timeout in seconds.
    ///   - apiVersion: Optional API version query (default `2024-02-15`).
    ///   - additionalHeaders: Optional extra HTTP headers (e.g. `x-ms-tenant-id`, custom auth). Applied after default headers.
    public init(
        endpoint: String,
        deployment: String,
        apiKey: String,
        timeout: TimeInterval = 60,
        apiVersion: String = "2024-02-15",
        additionalHeaders: [String: String]? = nil
    ) {
        self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deployment = deployment
        self.apiKey = apiKey
        self.timeout = timeout
        self.apiVersion = apiVersion
        self.additionalHeaders = additionalHeaders
    }

    public func complete(prompt: String) async throws -> String {
        let url1 = URL(string: "https://rathishk24-2173-text-su-resource.openai.azure.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url1)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Azure typically expects api-key header (Bearer can require RBAC); send both for compatibility.
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // Same structure as GroqClient/OpenAIClient: model, temperature, max_tokens, response_format, messages
        let body: [String: Any] = [
            "model": deployment,
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
            throw AIClientError.invalidResponse
        }
        print("[AzureOpenAIClient] HTTP \(http.statusCode) – responseLength: \(data.count)")
        if http.statusCode != 200 {
            let errMsg = Self.parseError(data, statusCode: http.statusCode)
            let bodyPreview = String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "nil"
            print("[AzureOpenAIClient] HTTP \(http.statusCode) – \(errMsg) body: \(bodyPreview)")
            throw AIClientError.apiError(errMsg)
        }
        let content: String
        do {
            content = try Self.parseResponse(data)
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? "nil"
            print("[AzureOpenAIClient] parseResponse failed – response body: \(bodyPreview)")
            throw error
        }
        print("[AzureOpenAIClient] success – responseLength: \(content.count)")
        return content
    }

    /// Parsing: same as Groq (content string first). Fallback for Azure when content is array of parts (e.g. [{"type":"text","text":"..."}]).
    /// Internal for testing with fixture responses.
    static func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIClientError.invalidResponse
        }
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let content = message["content"] as? String {
            return trim(content)
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { part -> String? in
                guard part["type"] as? String == "text", let t = part["text"] as? String else { return nil }
                return t
            }.joined()
            if !text.isEmpty { return trim(text) }
        }
        throw AIClientError.invalidResponse
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
