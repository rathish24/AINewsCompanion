import Foundation

public enum TTSProvider: String, CaseIterable, Sendable, Codable {
    case sarvam
    case elevenLabs

    public var displayName: String {
        switch self {
        case .sarvam: return "Sarvam AI"
        case .elevenLabs: return "ElevenLabs"
        }
    }
}

public enum SpeechLanguage: String, CaseIterable, Sendable, Codable {
    case english = "en-IN"
    case hindi = "hi-IN"
    case tamil = "ta-IN"
    case telugu = "te-IN"
    case malayalam = "ml-IN"
    case gujarati = "gu-IN"

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .hindi: return "Hindi"
        case .tamil: return "Tamil"
        case .telugu: return "Telugu"
        case .malayalam: return "Malayalam"
        case .gujarati: return "Gujarati"
        }
    }
}

public struct SpeechConfig: Sendable {
    public var provider: TTSProvider
    public var sarvamApiKey: String?
    public var elevenLabsApiKey: String?
    public var language: SpeechLanguage
    public var voice: String
    public var rate: Double

    public init(
        provider: TTSProvider = .elevenLabs,
        sarvamApiKey: String? = nil,
        elevenLabsApiKey: String? = nil,
        language: SpeechLanguage = .english,
        voice: String = "Rachel",
        rate: Double = 1.0
    ) {
        self.provider = provider
        self.sarvamApiKey = sarvamApiKey
        self.elevenLabsApiKey = elevenLabsApiKey
        self.language = language
        self.voice = voice
        self.rate = rate
    }
}
