import Foundation

/// AWS Bedrock (or custom inference endpoint) client for article-to-summary.
/// Conforms to `AICompleting`; pass the model ID available on your AWS server (e.g. `anthropic.claude-3-sonnet-20240229-v1:0`).
/// Use a custom endpoint URL if you have a proxy that forwards to Bedrock and accepts an API key; otherwise Bedrock requires AWS SigV4 (handle auth in your app).
/// API key can be empty for local validation; requests will fail at runtime until you provide a valid key or signed auth.
public final class AWSBedrockClient: AICompleting, Sendable {

    private let endpoint: String
    private let modelId: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let additionalHeaders: [String: String]?

    /// - Parameters:
    ///   - endpoint: Full URL to your inference endpoint. Use your Bedrock proxy (e.g. `https://your-proxy.example.com/invoke`) that accepts `x-api-key` or `Authorization`, or the Bedrock runtime URL if you inject signed headers elsewhere.
    ///   - modelId: Model ID on your server (e.g. `anthropic.claude-3-sonnet-20240229-v1:0`, `meta.llama3-70b-instruct-v1:0`).
    ///   - apiKey: API key for your proxy, or empty to only validate client creation.
    ///   - timeout: Request timeout in seconds.
    ///   - additionalHeaders: Optional extra HTTP headers (e.g. custom auth, tracing). Applied after default headers.
    public init(
        endpoint: String,
        modelId: String,
        apiKey: String,
        timeout: TimeInterval = 60,
        additionalHeaders: [String: String]? = nil
    ) {
        self.endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.modelId = modelId
        self.apiKey = apiKey
        self.timeout = timeout
        self.additionalHeaders = additionalHeaders
    }

    /// Convenience initializer using AWS Bedrock runtime URL for a region. You must still provide auth (e.g. via a proxy or by signing requests in your app).
    /// - Parameters:
    ///   - region: AWS region (e.g. `us-east-1`).
    ///   - modelId: Bedrock model ID.
    ///   - apiKey: Optional; Bedrock normally uses IAM/SigV4. Use this if your app calls a proxy that uses this key.
    ///   - timeout: Request timeout.
    ///   - additionalHeaders: Optional extra HTTP headers.
    public convenience init(
        region: String,
        modelId: String,
        apiKey: String = "",
        timeout: TimeInterval = 60,
        additionalHeaders: [String: String]? = nil
    ) {
        self.init(
            endpoint: "https://bedrock-runtime.\(region).amazonaws.com",
            modelId: modelId,
            apiKey: apiKey,
            timeout: timeout,
            additionalHeaders: additionalHeaders
        )
    }

    public func complete(prompt: String) async throws -> String {
        // Bedrock InvokeModel path; for a custom proxy, endpoint may already include path.
        let urlString = endpoint.contains("amazonaws.com") ? "\(endpoint)/model/\(modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId)/invoke" : endpoint
        guard let url = URL(string: urlString) else {
            print("[AWSBedrockClient] invalid URL – endpoint: \(endpoint.prefix(60))...")
            throw AIClientError.apiError("Invalid AWS endpoint URL")
        }
        print("[AWSBedrockClient] request – url: \(url.absoluteString.prefix(80))... modelId: \(modelId) promptLength: \(prompt.count)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.timeoutInterval = timeout
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // Bedrock Claude / common format: body with prompt in message format.
        let body: [String: Any] = [
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "temperature": 0.2,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[AWSBedrockClient] invalid response (not HTTPURLResponse)")
            throw AIClientError.invalidResponse
        }
        if http.statusCode != 200 {
            let msg = Self.parseError(data, statusCode: http.statusCode)
            print("[AWSBedrockClient] HTTP \(http.statusCode) – \(msg)")
            throw AIClientError.apiError(msg)
        }
        let content = try Self.parseBedrockResponse(data)
        print("[AWSBedrockClient] success – responseLength: \(content.count)")
        return content
    }

    private static func parseBedrockResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let block = content.first,
              let text = block["text"] as? String else {
            throw AIClientError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseError(_ data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return "HTTP \(statusCode)"
    }
}
