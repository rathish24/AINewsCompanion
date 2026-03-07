import Foundation
import SwiftData
import NewsCompanionKit

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
