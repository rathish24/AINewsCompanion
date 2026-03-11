import Foundation
import SwiftData
import NewsCompanionKit
import SummaryToAudio

/// Owns audio playback state and logic: which article is playing, play/pause, text cache (SwiftData), and completion.
///
/// Comparison (English vs non-English) — same flow shape, different translation source and cache keys:
///
/// | Aspect              | Sarvam (non-English)                    | ElevenLabs (non-English)                          | Azure (non-English)                    |
/// |---------------------|------------------------------------------|---------------------------------------------------|----------------------------------------|
/// | Cache key           | en-IN, ta-IN, hi-IN, …                   | en, fr, de, ta, … (29 langs)                      | en, fr, ta, hi, … (Azure locales)       |
/// | Translation source  | Sarvam API only                         | Translation API or custom translator              | Azure Translator or setAzureTranslator  |
/// | Stale cache check   | If cached == source → delete, don't use | Same                                              | Same                                    |
/// | Translation failure | Fallback: cached "en-IN" or fullText    | Fallback: cached "en" or fullText                 | Fallback: cached "en" or fullText       |
/// | Play on failure     | .sarvam(.english)                       | .elevenLabs(.english)                             | .azure(.englishUS)                      |
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

    /// Stops current playback and clears state. Call when the user changes TTS language so the next play uses the new language instead of continuing the old audio.
    func stopPlayback() {
        playTask?.cancel()
        speaker.stop()
        playingURL = nil
        preparingURL = nil
    }

    /// - Parameters:
    ///   - fetchSummaryWhenCacheMisses: When non-nil, a cache miss will fetch summary with this closure, save to cache, and play audio (no sheet). When nil, a cache miss calls `onOpenCompanion(url)` (open companion sheet). Use the former for "audio-only" or "combined" apps that have a companion config at init.
    func togglePlayPause(
        for url: URL,
        modelContext: ModelContext,
        effectiveLanguage: EffectiveTTSLanguage,
        onOpenCompanion: (URL) -> Void,
        fetchSummaryWhenCacheMisses: ((URL) async throws -> CompanionResult)? = nil
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
        playSummary(for: url, modelContext: modelContext, effectiveLanguage: effectiveLanguage, onOpenCompanion: onOpenCompanion, fetchSummaryWhenCacheMisses: fetchSummaryWhenCacheMisses)
    }

    func playSummary(
        for url: URL,
        modelContext: ModelContext,
        effectiveLanguage: EffectiveTTSLanguage,
        onOpenCompanion: (URL) -> Void,
        fetchSummaryWhenCacheMisses: ((URL) async throws -> CompanionResult)? = nil
    ) {
        if let cached = CompanionCache.cachedResult(for: url, modelContext: modelContext) {
            playingURL = url
            preparingURL = url
            playTask?.cancel()
            playGeneration += 1
            let generation = playGeneration
            playTask = Task { @MainActor in
                defer {
                    preparingURL = nil
                    if playGeneration == generation { self.playTask = nil }
                }
                speaker.playerManager.setError(nil)
                await playCachedSummaryAsync(url: url, cached: cached, modelContext: modelContext, effectiveLanguage: effectiveLanguage)
            }
            return
        }
        // Cache miss: either fetch in background and play (audio-only/combined), or open companion sheet.
        if let fetch = fetchSummaryWhenCacheMisses {
            playingURL = url
            preparingURL = url
            playTask?.cancel()
            playGeneration += 1
            let generation = playGeneration
            playTask = Task { @MainActor in
                defer {
                    preparingURL = nil
                    if playGeneration == generation { self.playTask = nil }
                }
                speaker.playerManager.setError(nil)
                do {
                    let result = try await fetch(url)
                    try CompanionCache.save(result: result, for: url, modelContext: modelContext)
                    if !Task.isCancelled, playingURL == url, let cached = CompanionCache.cachedResult(for: url, modelContext: modelContext) {
                        await playCachedSummaryAsync(url: url, cached: cached, modelContext: modelContext, effectiveLanguage: effectiveLanguage)
                    }
                } catch {
                    if !Task.isCancelled, playingURL == url {
                        speaker.playerManager.setError(error.localizedDescription)
                        speaker.playerManager.setLoading(false)
                    }
                    preparingURL = nil
                }
            }
            return
        }
        onOpenCompanion(url)
    }

    @MainActor
    private func playCachedSummaryAsync(
        url: URL,
        cached: CompanionResult,
        modelContext: ModelContext,
        effectiveLanguage: EffectiveTTSLanguage
    ) async {
        let fullText = cached.textForSpeech
        let langKey = effectiveLanguage.cacheKey

        if let cachedText = TranslationCache.cachedTranslation(for: url, languageCode: langKey, modelContext: modelContext) {
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
                switch effectiveLanguage.provider {
                case .sarvam: effectiveForPlay = .sarvam(.english)
                case .elevenLabs: effectiveForPlay = .elevenLabs(.english)
                case .azure: effectiveForPlay = .azure(.englishUS)
                }
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
