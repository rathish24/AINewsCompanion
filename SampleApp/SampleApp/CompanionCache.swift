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

// MARK: - App 2 cache adapter (CompanionResultCaching)

/// Bridges SwiftData-backed CompanionCache to NewsCompanionKit.CompanionResultCaching so App 2 can use `resultFetcher(config:cache:)`.
@MainActor
final class CompanionCacheAdapter: NewsCompanionKit.CompanionResultCaching {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func cachedResult(for url: URL) async -> CompanionResult? {
        CompanionCache.cachedResult(for: url, modelContext: modelContext)
    }

    func save(result: CompanionResult, for url: URL) async {
        try? CompanionCache.save(result: result, for: url, modelContext: modelContext)
    }
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
    /// Bump when translation logic changes so old (e.g. untranslated) entries are ignored.
    var cacheVersion: Int = 1

    init(url: URL, languageCode: String, translatedText: String) {
        self.urlString = url.absoluteString
        self.languageCode = languageCode
        self.translatedText = translatedText
        self.createdAt = Date()
        self.cacheVersion = TranslationCache.cacheVersion
    }

    init() {}
}

enum TranslationCache {
    /// Bump when translation behavior changes (e.g. ElevenLabs now gets real translation) so stale entries are ignored.
    static let cacheVersion = 2
    /// How long to keep a cached translation before refetching (e.g. 7 days).
    static let cacheValidityDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Returns the cached "text to speak" for (url, languageCode), or nil if missing/expired or wrong version.
    /// Pass effectiveLanguage.cacheKey so the same cache works for both Sarvam and ElevenLabs.
    static func cachedTranslation(for url: URL, languageCode: String, modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<CachedTranslation>(
            predicate: #Predicate<CachedTranslation> { $0.urlString == url.absoluteString && $0.languageCode == languageCode }
        )
        guard let cached = try? modelContext.fetch(descriptor).first else { return nil }
        guard cached.cacheVersion == cacheVersion else { return nil }
        guard Date().timeIntervalSince(cached.createdAt) < cacheValidityDuration else {
            try? modelContext.delete(cached)
            try? modelContext.save()
            return nil
        }
        return cached.translatedText
    }

    /// Removes cached translation for (url, languageCode). Use when entry is stale (e.g. untranslated).
    static func delete(url: URL, languageCode: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<CachedTranslation>(
            predicate: #Predicate<CachedTranslation> { $0.urlString == url.absoluteString && $0.languageCode == languageCode }
        )
        for existing in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(existing)
        }
        try? modelContext.save()
    }

    /// Saves the "text to speak" for (url, languageCode). Overwrites any existing entry for that key.
    static func save(translatedText: String, for url: URL, languageCode: String, modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<CachedTranslation>(
            predicate: #Predicate<CachedTranslation> { $0.urlString == url.absoluteString && $0.languageCode == languageCode }
        )
        for existing in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(existing)
        }
        let cached = CachedTranslation(url: url, languageCode: languageCode, translatedText: translatedText)
        modelContext.insert(cached)
        try modelContext.save()
    }
}
