import Foundation
import Combine

@MainActor
public final class SummaryToAudio: ObservableObject {
    public static let shared = SummaryToAudio()
    
    @Published public private(set) var config: SpeechConfig
    public let playerManager = AudioPlayerManager()
    
    private let sarvamClient = SarvamAIClient()
    private let elevenLabsClient = ElevenLabsClient()
    private let translationAPIClient = TranslationAPIClient()
    private let awsPollyClient = AWSPollyClient()
    private let awsTranslateClient = AWSTranslateServiceClient()
    private var cancellables = Set<AnyCancellable>()
    /// When set, used to translate text for ElevenLabs non-English (overrides built-in translation API).
    private var elevenLabsTranslator: (@Sendable (String, String) async throws -> String)?

    private var lastAudioData: Data?
    private var lastText: String?
    private var lastLanguageKey: String?
    private var lastProvider: TTSProvider?

    private init() {
        self.config = SpeechConfig()
        playerManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
    
    /// Clears the in-memory replay cache so the next play always fetches/generates new audio. Call when the user switches TTS provider or language so previous (e.g. Sarvam Tamil) audio is never replayed.
    public func clearReplayCache() {
        lastAudioData = nil
        lastText = nil
        lastLanguageKey = nil
        lastProvider = nil
    }

    public func configure(
        provider: TTSProvider? = nil,
        elevenLabsKey: String? = nil,
        sarvamKey: String? = nil,
        awsAccessKeyId: String? = nil,
        awsSecretAccessKey: String? = nil,
        awsSessionToken: String? = nil,
        awsRegion: String? = nil,
        sarvamLanguage: SpeechLanguage? = nil,
        elevenLabsLanguage: ElevenLabsLanguage? = nil,
        awsPollyLanguage: AWSPollyLanguage? = nil,
        libreTranslateBaseURL: String? = nil,
        libreTranslateAPIKey: String? = nil
    ) {
        if let provider = provider {
            if config.provider != provider {
                playerManager.stop()
                clearReplayCache()
            }
            config.provider = provider
        }
        if let key = elevenLabsKey { config.elevenLabsApiKey = key }
        if let key = sarvamKey { config.sarvamApiKey = key }
        if let v = awsAccessKeyId { config.awsAccessKeyId = v }
        if let v = awsSecretAccessKey { config.awsSecretAccessKey = v }
        if let v = awsSessionToken { config.awsSessionToken = v }
        if let v = awsRegion { config.awsRegion = v }
        if let lang = sarvamLanguage { config.sarvamLanguage = lang }
        if let lang = elevenLabsLanguage { config.elevenLabsLanguage = lang }
        if let lang = awsPollyLanguage { config.awsPollyLanguage = lang }
        
        Task {
            if let sarvamKey = config.sarvamApiKey {
                await sarvamClient.configure(apiKey: sarvamKey)
            }
            if let elevenLabsKey = config.elevenLabsApiKey {
                await elevenLabsClient.configure(apiKey: elevenLabsKey)
            }
            await translationAPIClient.configure(libreTranslateBaseURL: libreTranslateBaseURL, libreTranslateAPIKey: libreTranslateAPIKey)

            if let accessKeyId = config.awsAccessKeyId,
               let secret = config.awsSecretAccessKey,
               let region = config.awsRegion,
               !accessKeyId.trimmingCharacters(in: .whitespaces).isEmpty,
               !secret.trimmingCharacters(in: .whitespaces).isEmpty,
               !region.trimmingCharacters(in: .whitespaces).isEmpty {
                await awsPollyClient.configure(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secret,
                    sessionToken: config.awsSessionToken,
                    region: region
                )
                await awsTranslateClient.configure(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secret,
                    sessionToken: config.awsSessionToken,
                    region: region
                )
            }
        }
    }

    /// Set a translator used when ElevenLabs is selected and language is not English. Closure receives (text, languageCode) and returns translated text.
    public func setElevenLabsTranslator(_ translator: (@Sendable (String, String) async throws -> String)?) {
        elevenLabsTranslator = translator
    }

    /// Returns the text that should be sent to TTS for the given effective language.
    /// Sarvam: uses only Sarvam's internal translate API (sarvamClient.translate). No TranslationAPIClient or ElevenLabs.
    /// ElevenLabs: Default (English) → pass-through to ElevenLabs; non-English (user-selected) → English summary → AWS Translate → ElevenLabs (or custom translator/TranslationAPIClient if AWS not configured).
    /// AWS Polly: English → pass-through; French → AWS Translate (SigV4) then send to Polly. No Sarvam/ElevenLabs.
    public func translateIfNeeded(text: String, effectiveLanguage: EffectiveTTSLanguage) async throws -> String {
        switch effectiveLanguage {
        case .sarvam(let lang):
            return try await textForSarvamTTS(sourceText: text, language: lang)
        case .elevenLabs(let lang):
            return try await textForElevenLabsTTS(sourceText: text, language: lang)
        case .awsPolly(let lang):
            return try await textForAWSPollyTTS(sourceText: text, language: lang)
        }
    }

    /// Sarvam-only path: returns text ready for Sarvam TTS. English → pass-through; other languages → Sarvam translate API only. No external translation client.
    private func textForSarvamTTS(sourceText: String, language: SpeechLanguage) async throws -> String {
        if language == .english { return sourceText }
        guard let key = config.sarvamApiKey else {
            throw NSError(domain: "SummaryToAudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sarvam API key not configured. Add SARVAM_API_KEY to use Tamil and other languages."])
        }
        await sarvamClient.configure(apiKey: key)
        return try await sarvamClient.translate(text: sourceText, targetLanguage: language)
    }

    /// ElevenLabs-only path: English (default) → pass-through to ElevenLabs; non-English (user selected via long-press) → translate English summary via AWS Translate, then send to ElevenLabs.
    private func textForElevenLabsTTS(sourceText: String, language: ElevenLabsLanguage) async throws -> String {
        if language == .english {
            print("[ElevenLabs flow] Default language (English): no translation, passing \(sourceText.count) chars directly to ElevenLabs.")
            return sourceText
        }
        // Non-English: use AWS Translate base API when configured (App 2 + ElevenLabs: POST TranslateText, same as base curl).
        if let accessKeyId = config.awsAccessKeyId,
           let secret = config.awsSecretAccessKey,
           let region = config.awsRegion,
           !accessKeyId.trimmingCharacters(in: .whitespaces).isEmpty,
           !secret.trimmingCharacters(in: .whitespaces).isEmpty,
           !region.trimmingCharacters(in: .whitespaces).isEmpty {
            print("[ElevenLabs flow] Non-English (\(language.languageCode)): calling AWS Translate base API (en → \(language.awsTranslateTargetCode)), then ElevenLabs. Source text: \(sourceText.count) chars.")
            await awsTranslateClient.configure(
                accessKeyId: accessKeyId,
                secretAccessKey: secret,
                sessionToken: config.awsSessionToken,
                region: region
            )
            let translated = try await awsTranslateClient.translateWithBaseAPI(text: sourceText, sourceLanguageCode: "en", targetLanguageCode: language.awsTranslateTargetCode)
            print("[ElevenLabs flow] AWS Translate base API done. Translated text: \(translated.count) chars → sending to ElevenLabs.")
            return translated
        }
        // Fallback when AWS is not configured: custom translator or TranslationAPIClient.
        print("[ElevenLabs flow] Non-English (\(language.languageCode)), AWS not configured: using fallback translator. Source: \(sourceText.count) chars.")
        if let translate = elevenLabsTranslator {
            return try await translate(sourceText, language.languageCode)
        }
        return try await translationAPIClient.translate(text: sourceText, targetLanguageCode: language.languageCode)
    }

    /// AWS Polly-only path: English → pass-through; French → AWS Translate API.
    private func textForAWSPollyTTS(sourceText: String, language: AWSPollyLanguage) async throws -> String {
        if language == .english { return sourceText }
        guard let accessKeyId = config.awsAccessKeyId,
              let secret = config.awsSecretAccessKey,
              let region = config.awsRegion,
              !accessKeyId.trimmingCharacters(in: .whitespaces).isEmpty,
              !secret.trimmingCharacters(in: .whitespaces).isEmpty,
              !region.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AWSTranslateServiceError.notConfigured
        }
        await awsTranslateClient.configure(
            accessKeyId: accessKeyId,
            secretAccessKey: secret,
            sessionToken: config.awsSessionToken,
            region: region
        )
        return try await awsTranslateClient.translate(text: sourceText, sourceLanguageCode: "en", targetLanguageCode: language.translateTargetCode)
    }

    /// Plays the given text as speech. When `textIsAlreadyTranslated` is true, `text` is used as the final script for TTS (no translation step); use this when you have cached translated text.
    public func play(text: String, effectiveLanguage: EffectiveTTSLanguage? = nil, textIsAlreadyTranslated: Bool = false) async {
        let effective = effectiveLanguage ?? config.effectiveLanguage()
        let langKey = effective.cacheKey

        // Replay cache: only reuse when text, language, and provider all match (use effective.provider so UI is source of truth).
        if text == lastText, langKey == lastLanguageKey, effective.provider == lastProvider, let data = lastAudioData {
            print("SummaryToAudio: Replaying cached audio")
            playerManager.play(data: data)
            return
        }

        // Use passed effective language as source of truth for TTS path (keeps in sync with UI even if config was stale).
        let providerForTTS = effective.provider
        print("SummaryToAudio: Requesting speech for text (\(text.count) chars): [\(text.prefix(50))...] provider: \(providerForTTS.displayName) lang: \(effective.displayName) preTranslated: \(textIsAlreadyTranslated)")
        if providerForTTS == .elevenLabs {
            print("[ElevenLabs flow] Start. effectiveLanguage=\(effective.displayName) (\(effective.cacheKey)).")
        }
        playerManager.setLoading(true)

        do {
            let textToSpeak: String
            if textIsAlreadyTranslated {
                textToSpeak = text
            } else {
                textToSpeak = try await translateIfNeeded(text: text, effectiveLanguage: effective)
            }

            let audioData: Data
            switch (providerForTTS, effective) {
            case (.sarvam, .sarvam(let lang)):
                // Sarvam-only: TTS via Sarvam AI only; translation (when needed) is done above via textForSarvamTTS/sarvamClient.translate.
                print("SummaryToAudio: Using Sarvam AI. Final text length: \(textToSpeak.count) chars")
                audioData = try await sarvamClient.generateSpeech(text: textToSpeak, language: lang)
            case (.elevenLabs, .elevenLabs(let lang)):
                // ElevenLabs-only: TTS via ElevenLabs; translation (when needed) is done above via textForElevenLabsTTS (translation API or custom translator). No Sarvam.
                print("[ElevenLabs flow] Calling ElevenLabs TTS: \(textToSpeak.count) chars, languageCode=\(lang.languageCode).")
                audioData = try await elevenLabsClient.generateSpeech(text: textToSpeak, languageCode: lang.languageCode)
                print("[ElevenLabs flow] ElevenLabs TTS done. Received \(audioData.count) bytes.")
            case (.awsSpeech, .awsPolly(let lang)):
                guard let accessKeyId = config.awsAccessKeyId,
                      let secret = config.awsSecretAccessKey,
                      let region = config.awsRegion,
                      !accessKeyId.trimmingCharacters(in: .whitespaces).isEmpty,
                      !secret.trimmingCharacters(in: .whitespaces).isEmpty,
                      !region.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw AWSPollyError.notConfigured
                }
                await awsPollyClient.configure(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secret,
                    sessionToken: config.awsSessionToken,
                    region: region
                )
                print("SummaryToAudio: Using AWS Polly lang=\(lang.languageCode)")
                do {
                    audioData = try await awsPollyClient.synthesize(text: textToSpeak, language: lang)
                } catch {
                    // Last-resort fallback: speak using English voice so "Play" always produces audio.
                    // (Polly may not support certain locales/voices in some regions.)
                    print("SummaryToAudio: AWS Polly failed for \(lang.languageCode), falling back to English. Error: \(error.localizedDescription)")
                    playerManager.setError("AWS Polly (\(lang.displayName)) unavailable. Playing in English.")
                    audioData = try await awsPollyClient.synthesize(text: textToSpeak, language: .english)
                }
            default:
                fatalError("Provider and effective language must match")
            }

            print("SummaryToAudio: Received \(audioData.count) bytes of audio data")

            lastAudioData = audioData
            lastText = textToSpeak
            lastLanguageKey = langKey
            lastProvider = providerForTTS

            playerManager.play(data: audioData)
        } catch {
            print("SummaryToAudio ERROR: \(error.localizedDescription)")
            playerManager.setError(error.localizedDescription)
            playerManager.setLoading(false)
        }
    }
    
    public func stop() {
        playerManager.stop()
    }

    public func pause() {
        playerManager.pause()
    }

    public func resume() {
        playerManager.resume()
    }
}
