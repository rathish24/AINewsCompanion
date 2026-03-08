import Foundation
import SwiftData
import SummaryToAudio

/// Owns audio playback state and logic: which article is playing, play/pause, translation cache, and completion.
@MainActor
final class SummaryPlaybackController: ObservableObject {
    @Published private(set) var playingURL: URL?
    /// URL we're currently preparing: fetching translatedText (cache or API) and/or generating TTS. Show loading until play starts.
    @Published private(set) var preparingURL: URL?
    
    private let speaker = SummaryToAudio.shared
    
    init() {
        speaker.playerManager.onPlaybackFinished = { [weak self] in
            Task { @MainActor in
                self?.playingURL = nil
            }
        }
    }
    
    func isPlaying(for url: URL) -> Bool {
        playingURL == url && speaker.playerManager.isPlaying
    }
    
    /// True while translatedText is being fetched (cache/API) or TTS is being generated — show loading over the audio icon until play starts.
    func isLoading(for url: URL) -> Bool {
        (playingURL == url && speaker.playerManager.isLoading) || (preparingURL == url)
    }
    
    func isPaused(for url: URL) -> Bool {
        playingURL == url && speaker.playerManager.isPaused
    }
    
    /// Show a “playing” state (either playing or paused) for this URL so we can show animation and pause icon.
    func isActive(for url: URL) -> Bool {
        playingURL == url && (speaker.playerManager.isPlaying || speaker.playerManager.isPaused)
    }
    
    func togglePlayPause(
        for url: URL,
        modelContext: ModelContext,
        selectedLanguage: SpeechLanguage,
        selectedTTSProvider: TTSProvider,
        onOpenCompanion: (URL) -> Void
    ) {
        if isPlaying(for: url) {
            speaker.pause()
            return
        }
        if isPaused(for: url) {
            speaker.resume()
            return
        }
        if playingURL != nil {
            speaker.stop()
            playingURL = nil
        }
        playSummary(for: url, modelContext: modelContext, selectedLanguage: selectedLanguage, selectedTTSProvider: selectedTTSProvider, onOpenCompanion: onOpenCompanion)
    }
    
    func playSummary(
        for url: URL,
        modelContext: ModelContext,
        selectedLanguage: SpeechLanguage,
        selectedTTSProvider: TTSProvider,
        onOpenCompanion: (URL) -> Void
    ) {
        guard let cached = CompanionCache.cachedResult(for: url, modelContext: modelContext) else {
            onOpenCompanion(url)
            return
        }
        
        playingURL = url
        preparingURL = url
        
        Task { @MainActor in
            defer { preparingURL = nil }
            let summary = cached.summary
            let bulletsText = summary.bullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { $0.hasSuffix(".") ? $0 : $0 + "." }
                .joined(separator: " ")
            
            let fullText = "\(summary.oneLiner.trimmingCharacters(in: .whitespacesAndNewlines)) \(bulletsText) Why it matters: \(summary.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines))"
            
            let effectiveLanguage: SpeechLanguage = selectedTTSProvider == .elevenLabs ? .english : selectedLanguage
            
            if let cachedText = TranslationCache.cachedTranslation(for: url, language: effectiveLanguage, modelContext: modelContext) {
                print("[TTS] translatedText source: CACHE (SwiftData) | url: \(url.absoluteString) | languageCode: \(effectiveLanguage.rawValue) | chars: \(cachedText.count)")
                CompanionDebug.log("[TTS] translatedText source: CACHE (SwiftData) | languageCode: \(effectiveLanguage.rawValue) | chars: \(cachedText.count)")
                await speaker.play(text: cachedText, language: selectedLanguage, textIsAlreadyTranslated: true)
                return
            }
            
            var textToSpeak: String
            if effectiveLanguage == .english {
                textToSpeak = fullText
            } else {
                do {
                    textToSpeak = try await speaker.translateIfNeeded(text: fullText, language: effectiveLanguage)
                } catch {
                    print("SummaryPlaybackController: Translation failed, using original: \(error.localizedDescription)")
                    textToSpeak = fullText
                }
            }
            try? TranslationCache.save(translatedText: textToSpeak, for: url, language: effectiveLanguage, modelContext: modelContext)
            
            print("[TTS] translatedText source: API RESPONSE (then saved to SwiftData) | url: \(url.absoluteString) | languageCode: \(effectiveLanguage.rawValue) | chars: \(textToSpeak.count)")
            CompanionDebug.log("[TTS] translatedText source: API RESPONSE | languageCode: \(effectiveLanguage.rawValue) | chars: \(textToSpeak.count) | saved to SwiftData")
            await speaker.play(text: textToSpeak, language: selectedLanguage, textIsAlreadyTranslated: true)
        }
    }
}
