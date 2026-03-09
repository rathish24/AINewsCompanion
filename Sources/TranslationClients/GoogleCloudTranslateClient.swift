import Foundation

/// Google Cloud Translation client. Translates text using the Cloud Translation API (v2).
///
/// Use an API key from Google Cloud Console (Translation API enabled), or configure a proxy that accepts a key.
/// For Vertex AI or service-account auth, use a proxy or pass the Bearer token via `additionalHeaders`.
/// Long text is chunked (max 5,000 characters per request) and results are joined.
public final class GoogleCloudTranslateClient: TextTranslating, Sendable {

    /// Max characters per request (conservative for v2 limits).
    public static let maxCharactersPerRequest = 5_000

    private let apiKey: String
    private let timeout: TimeInterval
    private let additionalHeaders: [String: String]?
    private let baseURL: String

    /// - Parameters:
    ///   - apiKey: Google Cloud API key with Translation API enabled. For server-side or Vertex, use a proxy and pass its key, or use `additionalHeaders` for Bearer token.
    ///   - timeout: Request timeout in seconds.
    ///   - baseURL: Base URL for the API (default `https://translation.googleapis.com/language/translate/v2`). Override for proxies or different endpoints.
    ///   - additionalHeaders: Optional headers (e.g. `Authorization: Bearer <token>`). Applied after default headers.
    public init(
        apiKey: String,
        timeout: TimeInterval = 30,
        baseURL: String = "https://translation.googleapis.com/language/translate/v2",
        additionalHeaders: [String: String]? = nil
    ) {
        self.apiKey = apiKey
        self.timeout = timeout
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.additionalHeaders = additionalHeaders
    }

    public func translate(
        text: String,
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let chunks = TranslationChunking.chunks(for: trimmed, maxCharacters: Self.maxCharactersPerRequest)
        var results: [String] = []
        for chunk in chunks {
            let translated = try await translateOne(chunk: chunk, sourceLanguageCode: sourceLanguageCode, targetLanguageCode: targetLanguageCode)
            results.append(translated)
        }
        return results.joined(separator: " ").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "  ", with: " ")
    }

    private func translateOne(chunk: String, sourceLanguageCode: String, targetLanguageCode: String) async throws -> String {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: chunk),
            URLQueryItem(name: "target", value: targetLanguageCode)
        ]
        if !sourceLanguageCode.isEmpty, sourceLanguageCode != "auto" {
            components.queryItems?.append(URLQueryItem(name: "source", value: sourceLanguageCode))
        }
        guard let url = components.url else { throw TranslationClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        request.httpBody = Data()

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationClientError.invalidResponse }
        if http.statusCode != 200 {
            throw TranslationClientError.apiError(Self.parseError(data, statusCode: http.statusCode))
        }
        return try Self.parseResponse(data)
    }

    private static func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let translations = dataObj["translations"] as? [[String: Any]],
              let first = translations.first,
              let text = first["translatedText"] as? String else {
            throw TranslationClientError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
