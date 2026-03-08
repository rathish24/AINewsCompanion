import Foundation
import SwiftData
import SummaryToAudio

/// Owns audio playback state and logic: which article is playing, play/pause, text cache (SwiftData), and completion.
///
/// Comparison (English vs non-English) — same flow shape, different translation source and cache keys:
///
/// | Aspect              | Sarvam (non-English)                    | ElevenLabs (non-English)                          |
/// |---------------------|------------------------------------------|---------------------------------------------------|
/// | Cache key           | en-IN, ta-IN, hi-IN, te-IN, ml-IN, gu-IN | en, fr, de, ta, hi, ar, … (29 langs)              |
/// | Translation source  | Sarvam API only (sarvamClient.translate) | Translation API or custom translator              |
/// | Stale cache check   | If cached == source → delete, don't use   | Same                                              |
/// | Translation failure | Fallback: cached "en-IN" or fullText     | Fallback: cached "en" or fullText                 |
/// | Play on failure     | .sarvam(.english)                        | .elevenLabs(.english)                             |
@MainActor
final class SummaryPlaybackController: ObservableObject {
    @Published private(set) var playingURL: URL?
    /// URL we're currently preparing: fetching translatedText (cache or API) and/or generating TTS. Show loading until play starts.
    @Published private(set) var preparingURL: URL?
    /// In-flight play task; cancelled when user starts play for another URL so we never play stale audio.
    private var playTask: Task<Void, Never>?
    private var playGeneration: Int = 0

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
        effectiveLanguage: EffectiveTTSLanguage,
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
        playSummary(for: url, modelContext: modelContext, effectiveLanguage: effectiveLanguage, onOpenCompanion: onOpenCompanion)
    }

    func playSummary(
        for url: URL,
        modelContext: ModelContext,
        effectiveLanguage: EffectiveTTSLanguage,
        onOpenCompanion: (URL) -> Void
    ) {
        guard let cached = CompanionCache.cachedResult(for: url, modelContext: modelContext) else {
            onOpenCompanion(url)
            return
        }

        playingURL = url
        preparingURL = url
        let langKey = effectiveLanguage.cacheKey  // Sarvam: en-IN, ta-IN, etc. ElevenLabs: en, fr, etc.

        playTask?.cancel()
        playGeneration += 1
        let generation = playGeneration
        playTask = Task { @MainActor in
            defer {
                preparingURL = nil
                if playGeneration == generation { playTask = nil }
            }
            speaker.playerManager.setError(nil)
            let summary = cached.summary
            let bulletsText = summary.bullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { $0.hasSuffix(".") ? $0 : $0 + "." }
                .joined(separator: " ")

            let fullText = "\(summary.oneLiner.trimmingCharacters(in: .whitespacesAndNewlines)) \(bulletsText) Why it matters: \(summary.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines))"

            if let cachedText = TranslationCache.cachedTranslation(for: url, languageCode: langKey, modelContext: modelContext) {
                // For non-English: avoid using cache if it's actually untranslated English (stale).
                let useCached: Bool
                if !effectiveLanguage.isEnglish {
                    let cachedTrimmed = cachedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sourceTrimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    useCached = cachedTrimmed != sourceTrimmed && !cachedTrimmed.isEmpty
                    if !useCached {
                        TranslationCache.delete(url: url, languageCode: langKey, modelContext: modelContext)
                    }
                } else {
                    useCached = true
                }
                if useCached {
                    print("[TTS] translatedText source: CACHE (SwiftData) | url: \(url.absoluteString) | languageCode: \(langKey) | chars: \(cachedText.count)")
                    CompanionDebug.log("[TTS] translatedText source: CACHE (SwiftData) | languageCode: \(langKey) | chars: \(cachedText.count)")
                    if !Task.isCancelled && playingURL == url {
                        await speaker.play(text: cachedText, effectiveLanguage: effectiveLanguage, textIsAlreadyTranslated: true)
                    }
                    return
                }
            }

            var textToSpeak: String
            var effectiveForPlay = effectiveLanguage
            var translationSucceeded = true
            if effectiveLanguage.isEnglish {
                textToSpeak = fullText
            } else {
                do {
                    textToSpeak = try await speaker.translateIfNeeded(text: fullText, effectiveLanguage: effectiveLanguage)
                } catch {
                    // Translation failed: use default English from cache or from response. Play in English (provider-specific cache key).
                    print("SummaryPlaybackController: Translation failed, using default English: \(error.localizedDescription)")
                    speaker.playerManager.setError(error.localizedDescription.isEmpty ? "Translation failed. Playing in English." : error.localizedDescription)
                    let englishCacheKey = effectiveLanguage.englishCacheKeyForFallback
                    if let cachedEnglish = TranslationCache.cachedTranslation(for: url, languageCode: englishCacheKey, modelContext: modelContext), !cachedEnglish.isEmpty {
                        textToSpeak = cachedEnglish
                        print("[TTS] Fallback: using cached English | url: \(url.absoluteString) | key: \(englishCacheKey) | chars: \(textToSpeak.count)")
                    } else {
                        textToSpeak = fullText
                        print("[TTS] Fallback: using source text (English) | url: \(url.absoluteString) | chars: \(textToSpeak.count)")
                    }
                    effectiveForPlay = effectiveLanguage.provider == .sarvam ? .sarvam(.english) : .elevenLabs(.english)
                    translationSucceeded = false
                    TranslationCache.delete(url: url, languageCode: langKey, modelContext: modelContext)
                }
            }
            if translationSucceeded {
                try? TranslationCache.save(translatedText: textToSpeak, for: url, languageCode: langKey, modelContext: modelContext)
                print("[TTS] translatedText source: API RESPONSE (then saved to SwiftData) | url: \(url.absoluteString) | languageCode: \(langKey) | chars: \(textToSpeak.count)")
                CompanionDebug.log("[TTS] translatedText source: API RESPONSE | languageCode: \(langKey) | chars: \(textToSpeak.count) | saved to SwiftData")
            } else {
                print("[TTS] translatedText NOT saved (translation failed) | languageCode: \(langKey)")
            }
            if !Task.isCancelled && playingURL == url {
                await speaker.play(text: textToSpeak, effectiveLanguage: effectiveForPlay, textIsAlreadyTranslated: true)
            }
        }
    }
}
