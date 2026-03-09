import Foundation

/// Azure OpenAI client for article-to-summary. Use your Azure OpenAI resource endpoint and deployment (model) name.
/// Conforms to `AICompleting`; pass the deployment name as the model you have available on your Azure server.
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
        self.endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.deployment = deployment
        self.apiKey = apiKey
        self.timeout = timeout
        self.apiVersion = apiVersion
        self.additionalHeaders = additionalHeaders
    }

    public func complete(prompt: String) async throws -> String {
        let urlString = "\(endpoint)/openai/deployments/\(deployment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deployment)/chat/completions?api-version=\(apiVersion)"
        guard let url = URL(string: urlString) else { throw AIClientError.apiError("Invalid Azure OpenAI endpoint URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = timeout
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": "You are a precise news companion. Always respond with valid JSON only."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 4096,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
        if http.statusCode != 200 {
            throw AIClientError.apiError(Self.parseError(data, statusCode: http.statusCode))
        }
        return try Self.parseResponse(data)
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
