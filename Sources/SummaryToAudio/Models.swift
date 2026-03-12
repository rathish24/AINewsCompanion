import Foundation

public enum TTSProvider: String, CaseIterable, Sendable, Codable {
    case sarvam
    case elevenLabs
    case awsSpeech

    public var displayName: String {
        switch self {
        case .sarvam: return "Sarvam AI"
        case .elevenLabs: return "ElevenLabs"
        case .awsSpeech: return "AWSpeech"
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

// MARK: - AWS Polly: only languages officially supported by Amazon Polly (see supported-languages.html).
// Indian languages beyond Hindi (e.g. Tamil, Telugu, Kannada, Malayalam) are not supported by Polly; use Sarvam tab for those.
public enum AWSPollyLanguage: String, CaseIterable, Sendable, Codable {
    case english = "en-US"
    case englishUK = "en-GB"
    case french = "fr-FR"
    case german = "de-DE"
    case spanish = "es-ES"
    case italian = "it-IT"
    case portugueseBrazil = "pt-BR"
    case hindi = "hi-IN"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case chineseMandarin = "zh-CN"
    case arabic = "ar-SA"
    case russian = "ru-RU"

    public var displayName: String {
        switch self {
        case .english: return "English (US)"
        case .englishUK: return "English (UK)"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .portugueseBrazil: return "Portuguese (Brazil)"
        case .hindi: return "Hindi"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .chineseMandarin: return "Chinese (Mandarin)"
        case .arabic: return "Arabic"
        case .russian: return "Russian"
        }
    }

    /// Language code for Polly DescribeVoices / SynthesizeSpeech (matches AWS docs).
    public var languageCode: String { rawValue }

    /// AWS Translate target language code for translation before TTS.
    public var translateTargetCode: String {
        switch self {
        case .english: return "en"
        case .englishUK: return "en"
        case .french: return "fr"
        case .german: return "de"
        case .spanish: return "es"
        case .italian: return "it"
        case .portugueseBrazil: return "pt"
        case .hindi: return "hi"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .chineseMandarin: return "zh"
        case .arabic: return "ar"
        case .russian: return "ru"
        }
    }

    /// Set of language codes that Amazon Polly officially supports (for validation / UI).
    public static let pollySupportedLanguageCodes: Set<String> = [
        "en-US", "en-GB", "en-IN", "en-AU", "en-NZ", "en-ZA", "en-SG",
        "fr-FR", "fr-CA", "fr-BE", "de-DE", "de-AT", "de-CH",
        "es-ES", "es-US", "es-MX", "it-IT", "pt-BR", "pt-PT",
        "hi-IN", "ja-JP", "ko-KR", "cmn-CN", "yue-CN", "arb", "ar-AE",
        "ru-RU", "nl-NL", "nl-BE", "pl-PL", "tr-TR", "sv-SE", "da-DK",
        "nb-NO", "fi-FI", "ro-RO", "cs-CZ", "ca-ES", "cy-GB", "is-IS"
    ]

    /// True if this language is in Polly's supported list (we use rawValue; Polly also uses cmn-CN for Mandarin).
    public var isPollySupported: Bool {
        if rawValue == "zh-CN" { return true } // Polly docs use cmn-CN; some APIs accept zh-CN
        if rawValue == "ar-SA" { return true } // Polly uses arb; ar-AE etc.
        return Self.pollySupportedLanguageCodes.contains(rawValue)
    }
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

    /// Target language code for AWS Translate. Matches languageCode except where AWS uses a different code (e.g. Filipino: ElevenLabs "fil" → AWS "tl").
    public var awsTranslateTargetCode: String {
        switch self {
        case .filipino: return "tl"  // AWS Translate uses "tl" for Filipino/Tagalog
        default: return languageCode
        }
    }
}

// MARK: - Provider-agnostic effective language (avoids coupling TTS clients)
public enum EffectiveTTSLanguage: Sendable {
    case sarvam(SpeechLanguage)
    case elevenLabs(ElevenLabsLanguage)
    case awsPolly(AWSPollyLanguage)

    public var cacheKey: String {
        switch self {
        case .sarvam(let lang): return lang.languageCode
        case .elevenLabs(let lang): return lang.languageCode
        case .awsPolly(let lang): return lang.languageCode
        }
    }

    public var displayName: String {
        switch self {
        case .sarvam(let lang): return lang.displayName
        case .elevenLabs(let lang): return lang.displayName
        case .awsPolly(let lang): return lang.displayName
        }
    }

    public var isEnglish: Bool {
        switch self {
        case .sarvam(let lang): return lang == .english
        case .elevenLabs(let lang): return lang == .english
        case .awsPolly(let lang): return lang == .english
        }
    }

    /// TTS provider for this effective language (so play() can use passed language as source of truth).
    public var provider: TTSProvider {
        switch self {
        case .sarvam: return .sarvam
        case .elevenLabs: return .elevenLabs
        case .awsPolly: return .awsSpeech
        }
    }

    /// Cache key to use when translation fails and we fall back to English (cached or source). Sarvam: "en-IN"; ElevenLabs: "en".
    public var englishCacheKeyForFallback: String {
        switch self {
        case .sarvam: return SpeechLanguage.english.languageCode
        case .elevenLabs: return ElevenLabsLanguage.english.languageCode
        case .awsPolly: return AWSPollyLanguage.english.languageCode
        }
    }
}

public struct SpeechConfig: Sendable {
    public var provider: TTSProvider
    public var sarvamApiKey: String?
    public var elevenLabsApiKey: String?
    public var awsAccessKeyId: String?
    public var awsSecretAccessKey: String?
    public var awsSessionToken: String?
    public var awsRegion: String?
    /// Used when provider is .sarvam.
    public var sarvamLanguage: SpeechLanguage
    /// Used when provider is .elevenLabs.
    public var elevenLabsLanguage: ElevenLabsLanguage
    /// Used when provider is .awsSpeech.
    public var awsPollyLanguage: AWSPollyLanguage
    public var voice: String
    public var rate: Double

    public init(
        provider: TTSProvider = .elevenLabs,
        sarvamApiKey: String? = nil,
        elevenLabsApiKey: String? = nil,
        awsAccessKeyId: String? = nil,
        awsSecretAccessKey: String? = nil,
        awsSessionToken: String? = nil,
        awsRegion: String? = nil,
        sarvamLanguage: SpeechLanguage = .english,
        elevenLabsLanguage: ElevenLabsLanguage = .english,
        awsPollyLanguage: AWSPollyLanguage = .english,
        voice: String = "Rachel",
        rate: Double = 1.0
    ) {
        self.provider = provider
        self.sarvamApiKey = sarvamApiKey
        self.elevenLabsApiKey = elevenLabsApiKey
        self.awsAccessKeyId = awsAccessKeyId
        self.awsSecretAccessKey = awsSecretAccessKey
        self.awsSessionToken = awsSessionToken
        self.awsRegion = awsRegion
        self.sarvamLanguage = sarvamLanguage
        self.elevenLabsLanguage = elevenLabsLanguage
        self.awsPollyLanguage = awsPollyLanguage
        self.voice = voice
        self.rate = rate
    }

    /// Effective language for the current provider (for cache key and API calls).
    public func effectiveLanguage() -> EffectiveTTSLanguage {
        switch provider {
        case .sarvam: return .sarvam(sarvamLanguage)
        case .elevenLabs: return .elevenLabs(elevenLabsLanguage)
        case .awsSpeech: return .awsPolly(awsPollyLanguage)
        }
    }
}
