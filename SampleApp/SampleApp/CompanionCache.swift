import Foundation
import SwiftData
import NewsCompanionKit

/// Caches companion results in SwiftData. Flow: new or dynamic URL → call API once → save here; same URL later → read from cache, no API.
@Model
final class CachedCompanionResult {
    var urlString: String = ""
    var resultData: Data = Data()
    var createdAt: Date = Date()

    init(url: URL, result: CompanionResult) throws {
        self.urlString = url.absoluteString
        self.resultData = try JSONEncoder().encode(result)
        self.createdAt = Date()
    }

    init() {}
}

enum CompanionCache {
    /// Cache validity duration. After this, we refetch from the API (treat as new URL).
    static let cacheValidityDuration: TimeInterval = 24 * 60 * 60 // 24 hours

    /// Returns cached result for this URL if present and not expired. Nil for new/dynamic URL or expired → caller will call API then save.
    static func cachedResult(for url: URL, modelContext: ModelContext) -> CompanionResult? {
        let key = url.absoluteString
        let descriptor = FetchDescriptor<CachedCompanionResult>(
            predicate: #Predicate<CachedCompanionResult> { $0.urlString == key }
        )
        guard let cached = try? modelContext.fetch(descriptor).first,
              Date().timeIntervalSince(cached.createdAt) < cacheValidityDuration,
              let result = try? JSONDecoder().decode(CompanionResult.self, from: cached.resultData) else {
            return nil
        }
        return result
    }

    /// Saves API result for this URL so next time we serve from SwiftData (no API hit).
    static func save(result: CompanionResult, for url: URL, modelContext: ModelContext) throws {
        // Replace any existing cache for this URL
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
