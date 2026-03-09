import Foundation

/// AWS Translate client. Translates text using the Amazon Translate API.
///
/// **Authentication:** Direct calls to `translate.{region}.amazonaws.com` require AWS Signature Version 4.
/// Use either:
/// 1. A **proxy** that forwards to AWS Translate and accepts an API key: set `endpoint` to the proxy URL and `apiKey` to your key, or
/// 2. **Direct AWS** with `region`: build the client with `region` and supply signed headers via `additionalHeaders` (e.g. from a separate SigV4 signer).
/// Long text is chunked (max 9,000 UTF-8 bytes per request; API limit 10,000) and results are joined.
public final class AWSTranslateClient: TextTranslating, Sendable {

    /// Max UTF-8 bytes per request (API limit 10,000; we use 9,000 for safety).
    public static let maxBytesPerRequest = 9_000

    private let endpoint: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let additionalHeaders: [String: String]?

    /// - Parameters:
    ///   - endpoint: Full URL to the Translate API (e.g. `https://translate.us-east-1.amazonaws.com`) or your proxy URL. When using direct AWS, you must add SigV4-signed headers via `additionalHeaders`.
    ///   - apiKey: API key when using a proxy; ignored for direct AWS (use `additionalHeaders` for auth).
    ///   - timeout: Request timeout in seconds.
    ///   - additionalHeaders: Optional headers (e.g. `Authorization` from SigV4). Applied after default headers.
    public init(
        endpoint: String,
        apiKey: String = "",
        timeout: TimeInterval = 30,
        additionalHeaders: [String: String]? = nil
    ) {
        self.endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.timeout = timeout
        self.additionalHeaders = additionalHeaders
    }

    /// Convenience initializer using AWS region to build the Translate endpoint. Auth must be provided via `additionalHeaders` (e.g. SigV4) or use a proxy with `init(endpoint:apiKey:...)`.
    public convenience init(
        region: String,
        apiKey: String = "",
        timeout: TimeInterval = 30,
        additionalHeaders: [String: String]? = nil
    ) {
        self.init(
            endpoint: "https://translate.\(region).amazonaws.com",
            apiKey: apiKey,
            timeout: timeout,
            additionalHeaders: additionalHeaders
        )
    }

    public func translate(
        text: String,
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let chunks = TranslationChunking.chunksByBytes(for: trimmed, maxUTF8Bytes: Self.maxBytesPerRequest)
        var results: [String] = []
        for chunk in chunks {
            let translated = try await translateOne(chunk: chunk, sourceLanguageCode: sourceLanguageCode, targetLanguageCode: targetLanguageCode)
            results.append(translated)
        }
        return results.joined(separator: " ").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "  ", with: " ")
    }

    private func translateOne(chunk: String, sourceLanguageCode: String, targetLanguageCode: String) async throws -> String {
        guard let url = URL(string: endpoint) else { throw TranslationClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSShineFrontendService_20170701.TranslateText", forHTTPHeaderField: "X-Amz-Target")
        request.timeoutInterval = timeout
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = [
            "Text": chunk,
            "SourceLanguageCode": sourceLanguageCode,
            "TargetLanguageCode": targetLanguageCode
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationClientError.invalidResponse }
        if http.statusCode != 200 {
            throw TranslationClientError.apiError(Self.parseError(data, statusCode: http.statusCode))
        }
        return try Self.parseResponse(data)
    }

    private static func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translated = json["TranslatedText"] as? String else {
            throw TranslationClientError.invalidResponse
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseError(_ data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return "HTTP \(statusCode)"
    }
}
