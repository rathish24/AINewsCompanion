import Foundation

public enum AWSTranslateServiceError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "AWS Translate not configured. Add AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_DEFAULT_REGION."
        case .invalidURL: return "AWS Translate endpoint URL is invalid."
        case .invalidResponse: return "Invalid response from AWS Translate."
        case .apiError(let msg): return "AWS Translate error: \(msg)"
        }
    }
}

/// Amazon Translate client (direct AWS, SigV4). Decoupled from TTS clients.
/// API: POST https://translate.{region}.amazonaws.com with target `AWSShineFrontendService_20170701.TranslateText`.
/// Docs: https://docs.aws.amazon.com/translate/latest/APIReference/welcome.html
public actor AWSTranslateServiceClient {
    /// API limit 10,000 bytes; we use 9,000 for safety (same as `TranslationClients.AWSTranslateClient`).
    public static let maxBytesPerRequest = 9_000

    private var credentials: AWSSigV4Signer.Credentials?
    private var region: String?
    private var timeout: TimeInterval = 30

    public init() {}

    public func configure(
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        region: String,
        timeout: TimeInterval = 30
    ) {
        self.credentials = .init(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken)
        self.region = region
        self.timeout = timeout
    }

    public func translate(text: String, sourceLanguageCode: String = "en", targetLanguageCode: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        guard let credentials, let region else { throw AWSTranslateServiceError.notConfigured }

        print("[AWS Translate] translate called: source=\(sourceLanguageCode), target=\(targetLanguageCode), textLength=\(trimmed.count) chars, region=\(region).")
        let endpoint = "https://translate.\(region).amazonaws.com"
        guard let url = URL(string: endpoint) else { throw AWSTranslateServiceError.invalidURL }

        let chunks = chunksByBytes(for: trimmed, maxUTF8Bytes: Self.maxBytesPerRequest)
        if chunks.count > 1 {
            print("[AWS Translate] Chunked into \(chunks.count) requests (max \(Self.maxBytesPerRequest) bytes each).")
        }
        var results: [String] = []
        for chunk in chunks {
            let translated = try await translateOne(
                chunk: chunk,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode,
                url: url,
                credentials: credentials,
                region: region
            )
            results.append(translated)
        }
        let result = results.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "  ", with: " ")
        print("[AWS Translate] translate succeeded: resultLength=\(result.count) chars.")
        return result
    }

    private func translateOne(
        chunk: String,
        sourceLanguageCode: String,
        targetLanguageCode: String,
        url: URL,
        credentials: AWSSigV4Signer.Credentials,
        region: String
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSShineFrontendService_20170701.TranslateText", forHTTPHeaderField: "X-Amz-Target")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "Text": chunk,
            "SourceLanguageCode": sourceLanguageCode,
            "TargetLanguageCode": targetLanguageCode
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        try AWSSigV4Signer.sign(
            request: &request,
            body: bodyData,
            credentials: credentials,
            context: .init(service: "translate", region: region)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AWSTranslateServiceError.invalidResponse }
        if http.statusCode != 200 {
            let msg = Self.parseError(data, statusCode: http.statusCode)
            throw AWSTranslateServiceError.apiError(msg)
        }
        return try Self.parseResponse(data)
    }

    private static func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translated = json["TranslatedText"] as? String else {
            throw AWSTranslateServiceError.invalidResponse
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseError(_ data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String, !message.isEmpty { return message }
            if let type = json["__type"] as? String, let message = json["Message"] as? String {
                return "\(type): \(message)"
            }
        }
        return "HTTP \(statusCode)"
    }

    // MARK: - Chunking (UTF-8 bytes)

    private func chunksByBytes(for text: String, maxUTF8Bytes: Int) -> [String] {
        let utf8 = Array(text.utf8)
        guard utf8.count > maxUTF8Bytes else { return [text] }
        var result: [String] = []
        var start = 0
        while start < utf8.count {
            var end = min(start + maxUTF8Bytes, utf8.count)
            while end > start && (utf8[end - 1] & 0xC0) == 0x80 { end -= 1 }
            if let chunk = String(bytes: utf8[start..<end], encoding: .utf8), !chunk.isEmpty {
                result.append(chunk)
            }
            start = end
        }
        return result.isEmpty ? [String(text.prefix(1000))] : result
    }
}

