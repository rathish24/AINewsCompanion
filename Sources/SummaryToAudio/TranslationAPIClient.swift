import Foundation

/// Translates English text to a target language (e.g. fr, de, ar) for TTS.
/// Uses LibreTranslate when configured, otherwise MyMemory (free, chunked).
actor TranslationAPIClient {
    private var libreTranslateBaseURL: String?
    private var libreTranslateAPIKey: String?

    /// Configure LibreTranslate (optional). If not set, falls back to MyMemory.
    func configure(libreTranslateBaseURL: String? = nil, libreTranslateAPIKey: String? = nil) {
        self.libreTranslateBaseURL = libreTranslateBaseURL?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        self.libreTranslateAPIKey = libreTranslateAPIKey?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    private static let maxRetries = 3
    private static let retryDelaySeconds: UInt64 = 1

    /// Translate English text to target language code (e.g. "fr", "de", "ja", "zh").
    func translate(text: String, targetLanguageCode: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        if let base = libreTranslateBaseURL, let url = URL(string: base) {
            return try await withRetry { try await translateViaLibreTranslate(text: trimmed, target: targetLanguageCode, baseURL: url) }
        }
        return try await withRetry { try await translateViaMyMemory(text: trimmed, target: targetLanguageCode) }
    }

    private func withRetry<T>(operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<Self.maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < Self.maxRetries - 1 {
                    try? await Task.sleep(nanoseconds: Self.retryDelaySeconds * 1_000_000_000)
                }
            }
        }
        throw lastError!
    }

    // MARK: - LibreTranslate

    private func translateViaLibreTranslate(text: String, target: String, baseURL: URL) async throws -> String {
        let baseStr = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = baseStr.lowercased().hasSuffix("translate") ? baseStr : "\(baseStr)/translate"
        guard let url = URL(string: path) else { throw TranslationAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "q": text,
            "source": "en",
            "target": target,
            "format": "text"
        ]
        if let key = libreTranslateAPIKey, !key.isEmpty {
            body["api_key"] = key
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationAPIError.invalidResponse }
        if http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TranslationAPIError.apiError(msg)
        }
        struct LibreResponse: Decodable { let translatedText: String }
        let decoded = try JSONDecoder().decode(LibreResponse.self, from: data)
        return decoded.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - MyMemory (free, ~500 bytes per request → chunk)

    private static let myMemoryMaxBytes = 450

    private func translateViaMyMemory(text: String, target: String) async throws -> String {
        let chunks = chunkForMyMemory(text)
        var results: [String] = []
        for chunk in chunks {
            let translated = try await myMemorySingleRequest(text: chunk, target: target)
            results.append(translated)
        }
        return results.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func chunkForMyMemory(_ text: String) -> [String] {
        var chunks: [String] = []
        let maxBytes = Self.myMemoryMaxBytes
        var remaining = text.trimmingCharacters(in: .whitespaces)
        while !remaining.isEmpty {
            if remaining.utf8.count <= maxBytes {
                chunks.append(remaining)
                break
            }
            let bytes = Array(remaining.utf8)
            var take = min(maxBytes, bytes.count)
            var didChunk = false
            while take > 0 {
                guard let segment = String(bytes: bytes.prefix(take), encoding: .utf8) else {
                    take -= 1
                    continue
                }
                let chunk: String
                if let lastSpace = segment.lastIndex(of: " ") {
                    chunk = String(segment[..<lastSpace]).trimmingCharacters(in: .whitespaces)
                } else {
                    chunk = segment.trimmingCharacters(in: .whitespaces)
                }
                if !chunk.isEmpty { chunks.append(chunk) }
                let consumed = segment.utf8.count
                remaining = (String(bytes: Array(bytes.dropFirst(consumed)), encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespaces)
                didChunk = true
                break
            }
            if !didChunk {
                chunks.append(String(remaining.prefix(50)))
                break
            }
        }
        if chunks.isEmpty { chunks = [String(text.prefix(400))] }
        return chunks
    }

    private func myMemorySingleRequest(text: String, target: String) async throws -> String {
        var comp = URLComponents(string: "https://api.mymemory.translated.net/get")!
        comp.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|\(target)")
        ]
        guard let url = comp.url else { throw TranslationAPIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationAPIError.apiError("MyMemory HTTP error")
        }
        struct MyMemoryResponse: Decodable {
            let responseData: ResponseData?
            struct ResponseData: Decodable {
                let translatedText: String
            }
        }
        let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
        guard let translated = decoded.responseData?.translatedText else {
            throw TranslationAPIError.apiError("MyMemory no translation")
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public enum TranslationAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid translation API URL"
        case .invalidResponse: return "Invalid response from translation API"
        case .apiError(let msg): return msg
        }
    }
}
