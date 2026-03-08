import Foundation
import SwiftData
import NewsCompanionKit
import SummaryToAudio

@Model
final class CachedCompanionResult {
    var urlString: String = ""
    var resultData: Data = Data()
    var createdAt: Date = Date()
    var promptVersion: Int = 0

    init(url: URL, result: CompanionResult) throws {
        self.urlString = url.absoluteString
        self.resultData = try JSONEncoder().encode(result)
        self.createdAt = Date()
        self.promptVersion = CompanionCache.promptVersion
    }

    init() {}
}

enum CompanionCache {
    /// Bump this whenever the prompt or output contract changes so stale cache is ignored.
    static let promptVersion = 5
    static let cacheValidityDuration: TimeInterval = 24 * 60 * 60

    static func cachedResult(for url: URL, modelContext: ModelContext) -> CompanionResult? {
        let key = url.absoluteString
        let descriptor = FetchDescriptor<CachedCompanionResult>(
            predicate: #Predicate<CachedCompanionResult> { $0.urlString == key }
        )
        guard let cached = try? modelContext.fetch(descriptor).first else { return nil }
        guard cached.promptVersion == promptVersion else {
            CompanionDebug.log("CACHE STALE – prompt version changed – refetching – url: \(url.absoluteString)")
            return nil
        }
        guard Date().timeIntervalSince(cached.createdAt) < cacheValidityDuration else {
            CompanionDebug.log("CACHE EXPIRED – url: \(url.absoluteString)")
            return nil
        }
        guard let result = try? JSONDecoder().decode(CompanionResult.self, from: cached.resultData) else {
            CompanionDebug.log("CACHE DECODE FAILED – url: \(url.absoluteString)")
            return nil
        }
        return result
    }

    static func save(result: CompanionResult, for url: URL, modelContext: ModelContext) throws {
        let key = url.absoluteString
        let descriptor = FetchDescriptor<CachedCompanionResult>(
            predicate: #Predicate<CachedCompanionResult> { $0.urlString == key }
        )
        for existing in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(existing)
        }
        let cached = try CachedCompanionResult(url: url, result: result)
        modelContext.insert(cached)
        try modelContext.save()
    }
}

// MARK: - Translation cache (generic “text to speak” per url + language for TTS)

@Model
final class CachedTranslation {
    var urlString: String = ""
    var languageCode: String = ""
    var translatedText: String = ""
    var createdAt: Date = Date()

    init(url: URL, language: SpeechLanguage, translatedText: String) {
        self.urlString = url.absoluteString
        self.languageCode = language.rawValue
        self.translatedText = translatedText
        self.createdAt = Date()
    }

    init() {}
}

enum TranslationCache {
    /// How long to keep a cached translation before refetching (e.g. 7 days).
    static let cacheValidityDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Returns the cached "text to speak" for (url, language), or nil if missing/expired.
    /// Use `effectiveLanguage`: for ElevenLabs use `.english` (we don't translate); for Sarvam use the selected language.
    static func cachedTranslation(for url: URL, language: SpeechLanguage, modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<CachedTranslation>(
            predicate: #Predicate<CachedTranslation> { $0.urlString == url.absoluteString && $0.languageCode == language.rawValue }
        )
        guard let cached = try? modelContext.fetch(descriptor).first else { return nil }
        guard Date().timeIntervalSince(cached.createdAt) < cacheValidityDuration else {
            try? modelContext.delete(cached)
            try? modelContext.save()
            return nil
        }
        return cached.translatedText
    }

    /// Saves the "text to speak" for (url, language). Overwrites any existing entry for that key.
    static func save(translatedText: String, for url: URL, language: SpeechLanguage, modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<CachedTranslation>(
            predicate: #Predicate<CachedTranslation> { $0.urlString == url.absoluteString && $0.languageCode == language.rawValue }
        )
        for existing in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(existing)
        }
        let cached = CachedTranslation(url: url, language: language, translatedText: translatedText)
        modelContext.insert(cached)
        try modelContext.save()
    }
}
