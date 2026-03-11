import Foundation

// MARK: - Azure Speech Services TTS client (decoupled)
// Standalone client for Azure Text-to-Speech REST API. Translation for non-English is done externally
// (e.g. Azure Translator or custom translator); translated text is passed to generateSpeech(text:languageCode:).
// See: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech

public enum AzureSpeechError: Error, LocalizedError {
    case invalidURL
    case notConfigured
    case networkError(Error)
    case apiError(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Azure Speech endpoint URL."
        case .notConfigured: return "Azure Speech key or region not configured."
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .apiError(let code, let msg): return "Azure Speech API error (\(code)): \(msg)"
        case .invalidResponse: return "Invalid or empty audio response from Azure Speech."
        }
    }
}

/// Azure Text-to-Speech client using the REST API. Uses subscription key auth and returns MP3 audio.
public actor AzureSpeechClient {
    private var subscriptionKey: String?
    private var region: String = "eastus"
    /// Optional override; if nil, uses default voice for the given locale.
    private var voiceShortName: String?

    /// Output format: MP3 so it can be played with AVAudioPlayer without conversion.
    private static let outputFormat = "audio-24khz-96kbitrate-mono-mp3"
    private static let userAgent = "AINewsCompanion-SummaryToAudio"

    public init() {}

    public func configure(subscriptionKey: String, region: String, voiceShortName: String? = nil) {
        self.subscriptionKey = subscriptionKey
        self.region = region.trimmingCharacters(in: .whitespaces).lowercased()
        self.voiceShortName = voiceShortName
    }

    /// Builds the TTS endpoint URL for the configured region.
    private func synthesisURL() -> URL? {
        // Region identifier in URL (e.g. eastus -> eastus.tts.speech.microsoft.com)
        let host = "\(region).tts.speech.microsoft.com"
        return URL(string: "https://\(host)/cognitiveservices/v1")
    }

    /// Escapes text for use inside SSML.
    private static func escapeSSML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Generates speech for the given text. languageCode is the Azure locale (e.g. "en-US", "fr-FR", "ta-IN");
    /// if the locale has a known default voice we use it, otherwise we use a generic neural voice for that locale.
    public func generateSpeech(text: String, languageCode: String) async throws -> Data {
        guard let key = subscriptionKey, !key.isEmpty else {
            throw AzureSpeechError.notConfigured
        }
        guard let url = synthesisURL() else {
            throw AzureSpeechError.invalidURL
        }

        let locale = languageCode.contains("-") ? languageCode : localeFromLanguageCode(languageCode)
        let voiceName = voiceShortName ?? defaultVoiceForLocale(locale)
        let escaped = Self.escapeSSML(text)
        let ssml = """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(locale)'><voice name='\(voiceName)'>\(escaped)</voice></speak>
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.outputFormat, forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(ssml.utf8)
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AzureSpeechError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AzureSpeechError.invalidResponse
        }

        if http.statusCode != 200 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AzureSpeechError.apiError(http.statusCode, message)
        }

        guard !data.isEmpty else {
            throw AzureSpeechError.invalidResponse
        }

        return data
    }

    /// Map ISO 639-1 (e.g. "en", "fr") to Azure locale for SSML.
    private func localeFromLanguageCode(_ code: String) -> String {
        let map: [String: String] = [
            "en": "en-US", "fr": "fr-FR", "de": "de-DE", "es": "es-ES", "it": "it-IT",
            "pt": "pt-BR", "hi": "hi-IN", "ta": "ta-IN", "te": "te-IN", "ja": "ja-JP",
            "ko": "ko-KR", "zh": "zh-CN", "ar": "ar-SA", "nl": "nl-NL", "pl": "pl-PL",
            "ru": "ru-RU", "tr": "tr-TR"
        ]
        return map[code] ?? "en-US"
    }

    /// Default neural voice short name per locale (Azure standard voices).
    private func defaultVoiceForLocale(_ locale: String) -> String {
        let map: [String: String] = [
            "en-US": "en-US-JennyNeural", "en-GB": "en-GB-SoniaNeural",
            "fr-FR": "fr-FR-DeniseNeural", "de-DE": "de-DE-KatjaNeural",
            "es-ES": "es-ES-ElviraNeural", "it-IT": "it-IT-ElsaNeural",
            "pt-BR": "pt-BR-FranciscaNeural", "hi-IN": "hi-IN-SwaraNeural",
            "ta-IN": "ta-IN-PallaviNeural", "te-IN": "te-IN-ShrutiNeural",
            "ja-JP": "ja-JP-NanamiNeural", "ko-KR": "ko-KR-SunHiNeural",
            "zh-CN": "zh-CN-XiaoxiaoNeural", "ar-SA": "ar-SA-ZariyahNeural",
            "nl-NL": "nl-NL-ColetteNeural", "pl-PL": "pl-PL-ZofiaNeural",
            "ru-RU": "ru-RU-SvetlanaNeural", "tr-TR": "tr-TR-EmelNeural"
        ]
        return map[locale] ?? "en-US-JennyNeural"
    }
}
