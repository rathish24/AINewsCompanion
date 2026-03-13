import Foundation

/// AWS Bedrock (or custom inference endpoint) client for article-to-summary.
/// Conforms to `AICompleting`. Uses the **Converse API** only: `POST .../model/<id>/converse` with a single request/response shape for all models. [Converse API](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html).
/// When `apiKey` is set and endpoint is Bedrock, use `Authorization: Bearer <apiKey>` (e.g. `AWS_BEARER_TOKEN_BEDROCK`). For a custom proxy, `x-api-key` is sent instead.
public final class AWSBedrockClient: AICompleting, Sendable {

    private let endpoint: String
    private let modelId: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let additionalHeaders: [String: String]?

    /// - Parameters:
    ///   - endpoint: Full URL to your inference endpoint (e.g. `https://bedrock-runtime.us-east-1.amazonaws.com`) or a proxy URL that accepts `x-api-key`.
    ///   - modelId: Bedrock model ID (e.g. `meta.llama3-2-3b-instruct-v1:0`, `anthropic.claude-3-sonnet-20240229-v1:0`).
    ///   - apiKey: API key for a proxy; empty for direct Bedrock (requires SigV4 elsewhere).
    ///   - timeout: Request timeout in seconds.
    ///   - additionalHeaders: Optional extra HTTP headers (e.g. custom auth, tracing).
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

    /// Convenience initializer using AWS Bedrock runtime URL for a region.
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
        //Hardcoded endpoints
        let urlString = URL(string: endpoint)!
        var request = URLRequest(url: urlString)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
//        if !apiKey.isEmpty {
//            if isOfficialBedrock {
//                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//            } else {
//                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
//            }
//        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // Converse API only: same request shape for all models (no Llama/Anthropic-specific branches).
        let body: [String: Any] = [
            "messages": [
                [
                    "role": "user",
                    "content": [["text": prompt]]
                ]
            ],
            "inferenceConfig": [
                "maxTokens": 2500,
                "temperature": 0.2,
                "topP": 0.9
            ],
            "system": [
                ["text": "You are a precise news companion. Always respond with valid JSON only."]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        // MARK: - Request logging
        let bodyPreview = String(data: bodyData, encoding: .utf8) ?? "<invalid utf8>"
        print("[AWSBedrockClient] REQUEST URL: \(urlString)")
        print("[AWSBedrockClient] REQUEST METHOD: POST")
        print("[AWSBedrockClient] REQUEST HEADERS: \(request.allHTTPHeaderFields ?? [:])")
        print("[AWSBedrockClient] REQUEST BODY: \(bodyPreview)")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[AWSBedrockClient] ERROR (network): \(error)")
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            print("[AWSBedrockClient] ERROR: response was not HTTPURLResponse")
            throw AIClientError.invalidResponse
        }

        let responseBodyString = String(data: data, encoding: .utf8) ?? "<invalid utf8>"
        print("[AWSBedrockClient] RESPONSE STATUS: \(http.statusCode)")
        print("[AWSBedrockClient] RESPONSE HEADERS: \(http.allHeaderFields)")
        print("[AWSBedrockClient] RESPONSE BODY: \(responseBodyString)")

        if http.statusCode != 200 {
            let errorMessage = Self.parseError(data, statusCode: http.statusCode)
            print("[AWSBedrockClient] API ERROR: \(errorMessage)")
            throw AIClientError.apiError(errorMessage)
        }
        do {
            return try Self.parseConverseResponse(data)
        } catch {
            print("[AWSBedrockClient] PARSE ERROR: \(error); response body was: \(responseBodyString)")
            throw error
        }
    }

    /// Converse API response: output.message.content[] with "text" blocks.
    private static func parseConverseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let message = output["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            throw AIClientError.invalidResponse
        }
        let parts = content.compactMap { $0["text"] as? String }
        return parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseError(_ data: Data, statusCode: Int) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "HTTP \(statusCode)"
        }
        // AWS error shape: top-level "message" or "Error": { "Code", "Message" }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = json["Error"] as? [String: Any], let message = error["Message"] as? String, !message.isEmpty {
            return message
        }
        if statusCode == 403 {
            return "Access denied. AWS Bedrock requires IAM credentials (SigV4). Use a proxy that accepts an API key, or sign requests with the AWS SDK."
        }
        return "HTTP \(statusCode)"
    }
}
