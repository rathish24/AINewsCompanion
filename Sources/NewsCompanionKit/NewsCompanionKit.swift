import Foundation

/// Main API for the AI-powered news companion.
public enum NewsCompanionKit {

    public struct Config: Sendable {
        public var apiKey: String
        public var articleFetcher: (any ArticleFetching)?
        public var timeout: TimeInterval
        public var maxArticleLength: Int
        /// When set, the kit logs API request/response summary (no key or full body). Used for debug.
        public var debugLog: (@Sendable (String) -> Void)?

        public init(apiKey: String, articleFetcher: (any ArticleFetching)? = nil, timeout: TimeInterval = 25, maxArticleLength: Int = 12_000, debugLog: (@Sendable (String) -> Void)? = nil) {
            self.apiKey = apiKey
            self.articleFetcher = articleFetcher
            self.timeout = timeout
            self.maxArticleLength = maxArticleLength
            self.debugLog = debugLog
        }
    }

    /// Generates companion insights for the article at the given URL. Use the returned result to render the companion sheet.
    /// - Parameters:
    ///   - url: Article URL.
    ///   - config: Configuration including API key (supply key when ready).
    /// - Returns: Structured companion result, or throws on fetch/AI failure.
    public static func generate(url: URL, config: Config) async throws -> CompanionResult {
        do {
            config.debugLog?("API request starting – url: \(url.absoluteString)")
            let fetcher: any ArticleFetching = config.articleFetcher ?? ArticleFetcher(config: .init(maxArticleLength: config.maxArticleLength))
            let article = try await fetcher.fetch(url: url)
            config.debugLog?("Article fetched – title: \(article.title.prefix(60))...")
            guard !article.text.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NewsCompanionKitError.emptyArticle
            }
            config.debugLog?("Calling Gemini generateContent...")
            let aiClient = GeminiClient(apiKey: config.apiKey, timeout: config.timeout)
            let engine = ConversationEngine(aiClient: aiClient, maxArticleChars: config.maxArticleLength)
            let result = try await engine.generate(article: article)
            config.debugLog?("API response OK – oneLiner: \(result.summary.oneLiner.prefix(80))...")
            return result
        } catch {
            config.debugLog?("API failed – \(error.localizedDescription)")
            throw error
        }
    }
}

public enum NewsCompanionKitError: Error {
    case emptyArticle
}
