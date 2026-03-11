import Foundation

/// AWS Bedrock (or custom inference endpoint) client for article-to-summary.
/// Conforms to `AICompleting`. Supports:
/// - **Converse API** (Claude, Bearer token): `POST .../model/<id>/converse`, [Converse API](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html).
/// - **InvokeModel** (Llama or Claude legacy): `POST .../model/<id>/invoke`.
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
        let isOfficialBedrock = endpoint.contains("amazonaws.com")
        let useConverse = modelId.lowercased().contains("anthropic")
        let encodedModelId = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
        let pathSuffix = useConverse ? "converse" : "invoke"
        let urlString = "\(endpoint)/model/\(encodedModelId)/\(pathSuffix)"
        guard let url = URL(string: urlString) else { throw AIClientError.apiError("Invalid AWS endpoint URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            if isOfficialBedrock {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            } else {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            }
        }
        request.timeoutInterval = timeout
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any]
        let isLlama = modelId.lowercased().contains("meta.llama")

        if useConverse {
            // Converse API: messages + inferenceConfig (matches curl with Bearer token).
            body = [
                "messages": [
                    [
                        "role": "user",
                        "content": [["text": prompt]]
                    ]
                ],
                "inferenceConfig": [
                    "maxTokens": 4096,
                    "temperature": 0.2,
                    "topP": 0.9
                ],
                "system": [
                    ["text": "You are a precise news companion. Always respond with valid JSON only."]
                ]
            ]
        } else if isLlama {
            let systemInstruction = "You are a precise news companion. Always respond with valid JSON only."
            let formattedPrompt = Self.formatLlamaPrompt(system: systemInstruction, user: prompt)
            body = [
                "prompt": formattedPrompt,
                "max_gen_len": 4096,
                "temperature": 0.2,
                "top_p": 0.9
            ]
        } else {
            body = [
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 4096,
                "temperature": 0.2,
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
        if http.statusCode != 200 {
            throw AIClientError.apiError(Self.parseError(data, statusCode: http.statusCode))
        }
        if useConverse {
            return try Self.parseConverseResponse(data)
        }
        return try isLlama ? Self.parseLlamaResponse(data) : Self.parseClaudeResponse(data)
    }

    /// Llama 3 chat template: system + user, then assistant turn.
    private static func formatLlamaPrompt(system: String, user: String) -> String {
        """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>

        \(system)<|eot_id|><|start_header_id|>user<|end_header_id|>

        \(user)<|eot_id|><|start_header_id|>assistant<|end_header_id|>

        """
    }

    private static func parseClaudeResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let block = content.first,
              let text = block["text"] as? String else {
            throw AIClientError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func parseLlamaResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let generation = json["generation"] as? String else {
            throw AIClientError.invalidResponse
        }
        return generation.trimmingCharacters(in: .whitespacesAndNewlines)
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
