import Foundation

public enum TTSProvider: String, CaseIterable, Sendable, Codable {
    case sarvam
    case elevenLabs
    case system

    public var displayName: String {
        switch self {
        case .sarvam: return "Sarvam AI"
        case .elevenLabs: return "ElevenLabs"
        case .system: return "System (Free)"
        }
    }
}

// MARK: - Sarvam: Indian languages (used when TTS provider is Sarvam)
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

    /// Cache/key and API code for Sarvam.
    public var languageCode: String { rawValue }
}

// MARK: - ElevenLabs: all 29 languages supported by eleven_multilingual_v2
public enum ElevenLabsLanguage: String, CaseIterable, Sendable, Codable {
    case english = "en"
    case arabic = "ar"
    case bulgarian = "bg"
    case chinese = "zh"
    case croatian = "hr"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case filipino = "fil"
    case finnish = "fi"
    case french = "fr"
    case german = "de"
    case greek = "el"
    case hindi = "hi"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case malay = "ms"
    case polish = "pl"
    case portuguese = "pt"
    case romanian = "ro"
    case russian = "ru"
    case slovak = "sk"
    case spanish = "es"
    case swedish = "sv"
    case tamil = "ta"
    case turkish = "tr"
    case ukrainian = "uk"

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .arabic: return "Arabic"
        case .bulgarian: return "Bulgarian"
        case .chinese: return "Chinese"
        case .croatian: return "Croatian"
        case .czech: return "Czech"
        case .danish: return "Danish"
        case .dutch: return "Dutch"
        case .filipino: return "Filipino"
        case .finnish: return "Finnish"
        case .french: return "French"
        case .german: return "German"
        case .greek: return "Greek"
        case .hindi: return "Hindi"
        case .indonesian: return "Indonesian"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .malay: return "Malay"
        case .polish: return "Polish"
        case .portuguese: return "Portuguese"
        case .romanian: return "Romanian"
        case .russian: return "Russian"
        case .slovak: return "Slovak"
        case .spanish: return "Spanish"
        case .swedish: return "Swedish"
        case .tamil: return "Tamil"
        case .turkish: return "Turkish"
        case .ukrainian: return "Ukrainian"
        }
    }

    /// API and cache key for ElevenLabs (ISO 639-1 / BCP 47).
    public var languageCode: String { rawValue }
}

// MARK: - System TTS (AVSpeechSynthesizer — no API key required)
public enum SystemTTSLanguage: String, CaseIterable, Sendable, Codable {
    case english    = "en-US"
    case french     = "fr-FR"
    case german     = "de-DE"
    case spanish    = "es-ES"
    case italian    = "it-IT"
    case portuguese = "pt-BR"
    case arabic     = "ar-SA"
    case chinese    = "zh-CN"
    case japanese   = "ja-JP"
    case korean     = "ko-KR"
    case hindi      = "hi-IN"
    case dutch      = "nl-NL"
    case russian    = "ru-RU"
    case polish     = "pl-PL"
    case turkish    = "tr-TR"

    public var displayName: String {
        switch self {
        case .english:    return "English"
        case .french:     return "French"
        case .german:     return "German"
        case .spanish:    return "Spanish"
        case .italian:    return "Italian"
        case .portuguese: return "Portuguese"
        case .arabic:     return "Arabic"
        case .chinese:    return "Chinese"
        case .japanese:   return "Japanese"
        case .korean:     return "Korean"
        case .hindi:      return "Hindi"
        case .dutch:      return "Dutch"
        case .russian:    return "Russian"
        case .polish:     return "Polish"
        case .turkish:    return "Turkish"
        }
    }

    /// BCP 47 language tag passed to AVSpeechUtterance.
    public var languageCode: String { rawValue }
}

// MARK: - Provider-agnostic effective language (avoids coupling TTS clients)
public enum EffectiveTTSLanguage: Sendable {
    case sarvam(SpeechLanguage)
    case elevenLabs(ElevenLabsLanguage)
    case system(SystemTTSLanguage)

    public var cacheKey: String {
        switch self {
        case .sarvam(let lang): return lang.languageCode
        case .elevenLabs(let lang): return lang.languageCode
        case .system(let lang): return "sys_\(lang.languageCode)"
        }
    }

    public var displayName: String {
        switch self {
        case .sarvam(let lang): return lang.displayName
        case .elevenLabs(let lang): return lang.displayName
        case .system(let lang): return lang.displayName
        }
    }

    public var isEnglish: Bool {
        switch self {
        case .sarvam(let lang): return lang == .english
        case .elevenLabs(let lang): return lang == .english
        case .system(let lang): return lang == .english
        }
    }

    /// TTS provider for this effective language (so play() can use passed language as source of truth).
    public var provider: TTSProvider {
        switch self {
        case .sarvam: return .sarvam
        case .elevenLabs: return .elevenLabs
        case .system: return .system
        }
    }

    /// Cache key to use when translation fails and we fall back to English (cached or source). Sarvam: "en-IN"; ElevenLabs: "en"; System: "sys_en-US".
    public var englishCacheKeyForFallback: String {
        switch self {
        case .sarvam: return SpeechLanguage.english.languageCode
        case .elevenLabs: return ElevenLabsLanguage.english.languageCode
        case .system: return "sys_\(SystemTTSLanguage.english.languageCode)"
        }
    }
}

public struct SpeechConfig: Sendable {
    public var provider: TTSProvider
    public var sarvamApiKey: String?
    public var elevenLabsApiKey: String?
    /// Used when provider is .sarvam.
    public var sarvamLanguage: SpeechLanguage
    /// Used when provider is .elevenLabs.
    public var elevenLabsLanguage: ElevenLabsLanguage
    /// Used when provider is .system.
    public var systemLanguage: SystemTTSLanguage
    public var voice: String
    public var rate: Double

    public init(
        provider: TTSProvider = .elevenLabs,
        sarvamApiKey: String? = nil,
        elevenLabsApiKey: String? = nil,
        sarvamLanguage: SpeechLanguage = .english,
        elevenLabsLanguage: ElevenLabsLanguage = .english,
        systemLanguage: SystemTTSLanguage = .english,
        voice: String = "Rachel",
        rate: Double = 1.0
    ) {
        self.provider = provider
        self.sarvamApiKey = sarvamApiKey
        self.elevenLabsApiKey = elevenLabsApiKey
        self.sarvamLanguage = sarvamLanguage
        self.elevenLabsLanguage = elevenLabsLanguage
        self.systemLanguage = systemLanguage
        self.voice = voice
        self.rate = rate
    }

    /// Effective language for the current provider (for cache key and API calls).
    public func effectiveLanguage() -> EffectiveTTSLanguage {
        switch provider {
        case .sarvam:     return .sarvam(sarvamLanguage)
        case .elevenLabs: return .elevenLabs(elevenLabsLanguage)
        case .system:     return .system(systemLanguage)
        }
    }
}
