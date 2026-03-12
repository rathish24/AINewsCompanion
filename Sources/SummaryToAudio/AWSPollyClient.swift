import Foundation

public enum AWSPollyError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case apiError(String)
    case emptyAudio

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "AWS Polly not configured. Add AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_DEFAULT_REGION."
        case .invalidURL: return "AWS Polly endpoint URL is invalid."
        case .invalidResponse: return "Invalid response from AWS Polly."
        case .apiError(let msg): return "AWS Polly error: \(msg)"
        case .emptyAudio: return "AWS Polly returned empty audio."
        }
    }
}

/// Amazon Polly client (direct AWS, SigV4). Decoupled from other TTS providers.
/// API: POST https://polly.{region}.amazonaws.com/v1/speech
/// Docs: https://aws.amazon.com/polly/getting-started/
public actor AWSPollyClient {
    private var credentials: AWSSigV4Signer.Credentials?
    private var region: String?
    private var timeout: TimeInterval = 60
    private var voiceCache: [String: PollyVoiceChoice] = [:]

    public init() {}

    public func configure(
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        region: String,
        timeout: TimeInterval = 60
    ) {
        self.credentials = .init(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken)
        self.region = region
        self.timeout = timeout
        voiceCache.removeAll()
    }

    public func synthesize(text: String, language: AWSPollyLanguage) async throws -> Data {
        guard let credentials, let region else { throw AWSPollyError.notConfigured }

        let endpoint = "https://polly.\(region).amazonaws.com/v1/speech"
        guard let url = URL(string: endpoint) else { throw AWSPollyError.invalidURL }

        // Pick voice dynamically via DescribeVoices so we don't hardcode IDs (higher confidence across regions).
        // Prefer male voices, prefer neural engine when available.
        let choice = try await voiceChoice(for: language, credentials: credentials, region: region)

        // Prefer Neural when available; automatically fall back to Standard if region/voice doesn't support Neural.
        do {
            return try await synthesizeOnce(url: url, text: text, voiceId: choice.voiceId, engine: choice.engine, credentials: credentials, region: region)
        } catch let err as AWSPollyError {
            if case .apiError(let msg) = err, msg.localizedCaseInsensitiveContains("engine") {
                return try await synthesizeOnce(url: url, text: text, voiceId: choice.voiceId, engine: "standard", credentials: credentials, region: region)
            }
            throw err
        } catch {
            throw error
        }
    }

    private func synthesizeOnce(
        url: URL,
        text: String,
        voiceId: String,
        engine: String,
        credentials: AWSSigV4Signer.Credentials,
        region: String
    ) async throws -> Data {
        let body: [String: Any] = [
            "OutputFormat": "mp3",
            "Text": text,
            "VoiceId": voiceId,
            "Engine": engine
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        try AWSSigV4Signer.sign(
            request: &request,
            body: bodyData,
            credentials: credentials,
            context: .init(service: "polly", region: region)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AWSPollyError.invalidResponse }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AWSPollyError.apiError(msg)
        }
        guard !data.isEmpty else { throw AWSPollyError.emptyAudio }
        return data
    }

    // MARK: - DescribeVoices (dynamic selection)

    private struct PollyVoiceChoice: Sendable {
        let voiceId: String
        /// "neural" or "standard"
        let engine: String
    }

    private struct DescribeVoicesResponse: Decodable {
        let Voices: [Voice]
        struct Voice: Decodable {
            let Id: String
            let Gender: String?
            let LanguageCode: String?
            let SupportedEngines: [String]?
        }
    }

    /// Alternate Polly language codes when the primary (e.g. zh-CN) returns no voices; AWS docs use cmn-CN, arb, etc.
    private static func alternateLanguageCode(for language: AWSPollyLanguage) -> String? {
        switch language {
        case .chineseMandarin: return "cmn-CN"
        case .arabic: return "arb"
        default: return nil
        }
    }

    private func voiceChoice(
        for language: AWSPollyLanguage,
        credentials: AWSSigV4Signer.Credentials,
        region: String
    ) async throws -> PollyVoiceChoice {
        if let cached = voiceCache[language.languageCode] {
            return cached
        }

        let codesToTry = [language.languageCode] + [Self.alternateLanguageCode(for: language)].compactMap { $0 }
        var lastError: Error?
        for languageCode in codesToTry {
            do {
                let choice = try await fetchVoiceChoice(languageCode: languageCode, credentials: credentials, region: region)
                voiceCache[language.languageCode] = choice
                return choice
            } catch {
                lastError = error
            }
        }
        throw lastError ?? AWSPollyError.apiError("No Polly voices available for \(language.languageCode) in region \(region).")
    }

    private func fetchVoiceChoice(languageCode: String, credentials: AWSSigV4Signer.Credentials, region: String) async throws -> PollyVoiceChoice {
        let endpoint = "https://polly.\(region).amazonaws.com/v1/voices"
        guard var comp = URLComponents(string: endpoint) else { throw AWSPollyError.invalidURL }
        comp.queryItems = [URLQueryItem(name: "LanguageCode", value: languageCode)]
        guard let url = comp.url else { throw AWSPollyError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let emptyBody = Data()
        try AWSSigV4Signer.sign(
            request: &request,
            body: emptyBody,
            credentials: credentials,
            context: .init(service: "polly", region: region)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AWSPollyError.invalidResponse }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AWSPollyError.apiError(msg)
        }
        let decoded = try JSONDecoder().decode(DescribeVoicesResponse.self, from: data)
        guard !decoded.Voices.isEmpty else {
            throw AWSPollyError.apiError("No Polly voices available for \(languageCode) in region \(region).")
        }

        func enginePreference(for voice: DescribeVoicesResponse.Voice) -> String {
            let engines = (voice.SupportedEngines ?? []).map { $0.lowercased() }
            return engines.contains("neural") ? "neural" : "standard"
        }

        // Prefer male voices; then prefer neural engine; else first available.
        let males = decoded.Voices.filter { ($0.Gender ?? "").lowercased() == "male" }
        let candidates = males.isEmpty ? decoded.Voices : males
        let chosen = candidates.sorted {
            let e0 = enginePreference(for: $0)
            let e1 = enginePreference(for: $1)
            if e0 != e1 { return e0 == "neural" }
            return $0.Id < $1.Id
        }.first!

        return PollyVoiceChoice(voiceId: chosen.Id, engine: enginePreference(for: chosen))
    }
}

