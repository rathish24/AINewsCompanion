import Foundation
import Combine

@MainActor
public final class SummaryToAudio: ObservableObject {
    public static let shared = SummaryToAudio()
    
    @Published public private(set) var config: SpeechConfig
    public let playerManager = AudioPlayerManager()
    
    private let sarvamClient = SarvamAIClient()
    private let elevenLabsClient = ElevenLabsClient()
    private var cancellables = Set<AnyCancellable>()
    
    private var lastAudioData: Data?
    private var lastText: String?
    private var lastLanguage: SpeechLanguage?
    private var lastProvider: TTSProvider?

    private init() {
        self.config = SpeechConfig()
        playerManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
    
    public func configure(
        provider: TTSProvider? = nil,
        elevenLabsKey: String? = nil,
        sarvamKey: String? = nil,
        language: SpeechLanguage? = nil
    ) {
        if let provider = provider { config.provider = provider }
        if let key = elevenLabsKey { config.elevenLabsApiKey = key }
        if let key = sarvamKey { config.sarvamApiKey = key }
        if let lang = language { config.language = lang }
        
        Task {
            if let sarvamKey = config.sarvamApiKey {
                await sarvamClient.configure(apiKey: sarvamKey)
            }
            if let elevenLabsKey = config.elevenLabsApiKey {
                await elevenLabsClient.configure(apiKey: elevenLabsKey)
            }
        }
    }

    /// Returns the text that should be sent to TTS for the given language.
    /// For English returns `text` as-is; for other languages returns translated text via Sarvam (when configured).
    /// Use this to resolve "text to speak" before calling `play(text:language:textIsAlreadyTranslated:)` so you can cache the result (e.g. in SwiftData).
    public func translateIfNeeded(text: String, language: SpeechLanguage) async throws -> String {
        if language == .english {
            return text
        }
        guard config.sarvamApiKey != nil else {
            return text
        }
        return try await sarvamClient.translate(text: text, targetLanguage: language)
    }

    /// Plays the given text as speech. When `textIsAlreadyTranslated` is true, `text` is used as the final script for TTS (no translation step); use this when you have cached translated text.
    public func play(text: String, language: SpeechLanguage? = nil, textIsAlreadyTranslated: Bool = false) async {
        let lang = language ?? config.language
        
        // Replay cache check
        if text == lastText, lang == lastLanguage, config.provider == lastProvider, let data = lastAudioData {
            print("SummaryToAudio: Replaying cached audio")
            playerManager.play(data: data)
            return
        }

        print("SummaryToAudio: Requesting speech for text (\(text.count) chars): [\(text.prefix(50))...] provider: \(config.provider.displayName) lang: \(lang.displayName) preTranslated: \(textIsAlreadyTranslated)")
        playerManager.setLoading(true)
        
        do {
            let textToSpeak: String
            if textIsAlreadyTranslated {
                textToSpeak = text
            } else {
                switch config.provider {
                case .sarvam:
                    if lang != .english {
                        print("SummaryToAudio: Translating to \(lang.displayName)...")
                        textToSpeak = try await sarvamClient.translate(text: text, targetLanguage: lang)
                        print("SummaryToAudio: Translation complete. Length: \(textToSpeak.count) chars")
                    } else {
                        textToSpeak = text
                    }
                case .elevenLabs:
                    textToSpeak = text
                }
            }

            let audioData: Data
            switch config.provider {
            case .sarvam:
                print("SummaryToAudio: Using Sarvam AI. Final text length: \(textToSpeak.count) chars")
                audioData = try await sarvamClient.generateSpeech(text: textToSpeak, language: lang)
            case .elevenLabs:
                print("SummaryToAudio: Using ElevenLabs (Monolingual English)")
                audioData = try await elevenLabsClient.generateSpeech(text: textToSpeak)
            }
            
            print("SummaryToAudio: Received \(audioData.count) bytes of audio data")
            
            lastAudioData = audioData
            lastText = textToSpeak
            lastLanguage = lang
            lastProvider = config.provider
            
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
