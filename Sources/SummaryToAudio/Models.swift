import Foundation

public enum TTSProvider: String, CaseIterable, Sendable, Codable {
    case sarvam
    case elevenLabs
    case azure

    public var displayName: String {
        switch self {
        case .sarvam: return "Sarvam AI"
        case .elevenLabs: return "ElevenLabs"
        case .azure: return "Azure"
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

// MARK: - Azure Speech: locales and default neural voices (used when TTS provider is Azure)
public enum AzureSpeechLanguage: String, CaseIterable, Sendable, Codable {
    case englishUS = "en-US"
    case englishGB = "en-GB"
    case french = "fr-FR"
    case german = "de-DE"
    case spanish = "es-ES"
    case italian = "it-IT"
    case portugueseBR = "pt-BR"
    case hindi = "hi-IN"
    case tamil = "ta-IN"
    case telugu = "te-IN"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case chineseMandarin = "zh-CN"
    case arabic = "ar-SA"
    case dutch = "nl-NL"
    case polish = "pl-PL"
    case russian = "ru-RU"
    case turkish = "tr-TR"

    public var displayName: String {
        switch self {
        case .englishUS: return "English (US)"
        case .englishGB: return "English (GB)"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .portugueseBR: return "Portuguese (BR)"
        case .hindi: return "Hindi"
        case .tamil: return "Tamil"
        case .telugu: return "Telugu"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .chineseMandarin: return "Chinese (Mandarin)"
        case .arabic: return "Arabic"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .russian: return "Russian"
        case .turkish: return "Turkish"
        }
    }

    /// Locale for Azure TTS (SSML voice selection).
    public var locale: String { rawValue }

    /// ISO 639-1 style code for translation API (e.g. "en", "fr", "ta"). Used as cache key and for Azure Translator target.
    public var languageCode: String {
        String(rawValue.prefix(2))
    }

    /// Default neural voice short name for this locale (Azure Speech Service).
    public var defaultVoiceShortName: String {
        switch self {
        case .englishUS: return "en-US-JennyNeural"
        case .englishGB: return "en-GB-SoniaNeural"
        case .french: return "fr-FR-DeniseNeural"
        case .german: return "de-DE-KatjaNeural"
        case .spanish: return "es-ES-ElviraNeural"
        case .italian: return "it-IT-ElsaNeural"
        case .portugueseBR: return "pt-BR-FranciscaNeural"
        case .hindi: return "hi-IN-SwaraNeural"
        case .tamil: return "ta-IN-PallaviNeural"
        case .telugu: return "te-IN-ShrutiNeural"
        case .japanese: return "ja-JP-NanamiNeural"
        case .korean: return "ko-KR-SunHiNeural"
        case .chineseMandarin: return "zh-CN-XiaoxiaoNeural"
        case .arabic: return "ar-SA-ZariyahNeural"
        case .dutch: return "nl-NL-ColetteNeural"
        case .polish: return "pl-PL-ZofiaNeural"
        case .russian: return "ru-RU-SvetlanaNeural"
        case .turkish: return "tr-TR-EmelNeural"
        }
    }

    public static var english: AzureSpeechLanguage { .englishUS }
}

// MARK: - Provider-agnostic effective language (avoids coupling TTS clients)
public enum EffectiveTTSLanguage: Sendable {
    case sarvam(SpeechLanguage)
    case elevenLabs(ElevenLabsLanguage)
    case azure(AzureSpeechLanguage)

    public var cacheKey: String {
        switch self {
        case .sarvam(let lang): return lang.languageCode
        case .elevenLabs(let lang): return lang.languageCode
        case .azure(let lang): return lang.languageCode
        }
    }

    public var displayName: String {
        switch self {
        case .sarvam(let lang): return lang.displayName
        case .elevenLabs(let lang): return lang.displayName
        case .azure(let lang): return lang.displayName
        }
    }

    public var isEnglish: Bool {
        switch self {
        case .sarvam(let lang): return lang == .english
        case .elevenLabs(let lang): return lang == .english
        case .azure(let lang): return lang == .englishUS || lang == .englishGB
        }
    }

    /// TTS provider for this effective language (so play() can use passed language as source of truth).
    public var provider: TTSProvider {
        switch self {
        case .sarvam: return .sarvam
        case .elevenLabs: return .elevenLabs
        case .azure: return .azure
        }
    }

    /// Cache key to use when translation fails and we fall back to English (cached or source). Sarvam: "en-IN"; ElevenLabs: "en"; Azure: "en".
    public var englishCacheKeyForFallback: String {
        switch self {
        case .sarvam: return SpeechLanguage.english.languageCode
        case .elevenLabs: return ElevenLabsLanguage.english.languageCode
        case .azure: return AzureSpeechLanguage.englishUS.languageCode
        }
    }
}

public struct SpeechConfig: Sendable {
    public var provider: TTSProvider
    public var sarvamApiKey: String?
    public var elevenLabsApiKey: String?
    /// Used when provider is .azure: Speech resource key and region (e.g. "eastus").
    public var azureSpeechKey: String?
    public var azureSpeechRegion: String?
    /// Used when provider is .sarvam.
    public var sarvamLanguage: SpeechLanguage
    /// Used when provider is .elevenLabs.
    public var elevenLabsLanguage: ElevenLabsLanguage
    /// Used when provider is .azure.
    public var azureLanguage: AzureSpeechLanguage
    public var voice: String
    public var rate: Double

    public init(
        provider: TTSProvider = .elevenLabs,
        sarvamApiKey: String? = nil,
        elevenLabsApiKey: String? = nil,
        azureSpeechKey: String? = nil,
        azureSpeechRegion: String? = nil,
        sarvamLanguage: SpeechLanguage = .english,
        elevenLabsLanguage: ElevenLabsLanguage = .english,
        azureLanguage: AzureSpeechLanguage = .englishUS,
        voice: String = "Rachel",
        rate: Double = 1.0
    ) {
        self.provider = provider
        self.sarvamApiKey = sarvamApiKey
        self.elevenLabsApiKey = elevenLabsApiKey
        self.azureSpeechKey = azureSpeechKey
        self.azureSpeechRegion = azureSpeechRegion
        self.sarvamLanguage = sarvamLanguage
        self.elevenLabsLanguage = elevenLabsLanguage
        self.azureLanguage = azureLanguage
        self.voice = voice
        self.rate = rate
    }

    /// Effective language for the current provider (for cache key and API calls).
    public func effectiveLanguage() -> EffectiveTTSLanguage {
        switch provider {
        case .sarvam: return .sarvam(sarvamLanguage)
        case .elevenLabs: return .elevenLabs(elevenLabsLanguage)
        case .azure: return .azure(azureLanguage)
        }
    }
}
