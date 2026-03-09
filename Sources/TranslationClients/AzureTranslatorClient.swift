import Foundation

/// Azure Translator (Cognitive Services) client. Translates text using the Translator Text API v3.
///
/// Set your key and region in the Azure portal (Cognitive Services / Translator resource).
/// Long text is chunked (max 25,000 characters per request) and results are joined.
public final class AzureTranslatorClient: TextTranslating, Sendable {

    /// Max characters per request (Azure recommends under 50,000; we use 25,000 for safety).
    public static let maxCharactersPerRequest = 25_000

    private let endpoint: String
    private let subscriptionKey: String
    private let subscriptionRegion: String
    private let timeout: TimeInterval
    private let additionalHeaders: [String: String]?

    /// - Parameters:
    ///   - endpoint: Base URL (e.g. `https://api.cognitive.microsofttranslator.com`). Use regional endpoints like `https://api-nam.cognitive.microsofttranslator.com` if needed.
    ///   - subscriptionKey: Azure Translator subscription key (API key).
    ///   - subscriptionRegion: Region where the resource was created (e.g. `eastus`). Required for multi-service or regional resources.
    ///   - timeout: Request timeout in seconds.
    ///   - additionalHeaders: Optional extra HTTP headers.
    public init(
        endpoint: String = "https://api.cognitive.microsofttranslator.com",
        subscriptionKey: String,
        subscriptionRegion: String,
        timeout: TimeInterval = 30,
        additionalHeaders: [String: String]? = nil
    ) {
        self.endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.subscriptionKey = subscriptionKey
        self.subscriptionRegion = subscriptionRegion
        self.timeout = timeout
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
        var components = URLComponents(string: "\(endpoint)/translate")!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: targetLanguageCode)
        ]
        if !sourceLanguageCode.isEmpty, sourceLanguageCode != "auto" {
            components.queryItems?.append(URLQueryItem(name: "from", value: sourceLanguageCode))
        }
        guard let url = components.url else { throw TranslationClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue(subscriptionRegion, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        request.timeoutInterval = timeout
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body = [["Text": chunk]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationClientError.invalidResponse }
        if http.statusCode != 200 {
            throw TranslationClientError.apiError(Self.parseError(data, statusCode: http.statusCode))
        }
        return try Self.parseResponse(data)
    }

    private static func parseResponse(_ data: Data) throws -> String {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let translations = first["translations"] as? [[String: Any]],
              let trans = translations.first,
              let text = trans["text"] as? String else {
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
