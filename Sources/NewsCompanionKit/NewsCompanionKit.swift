import Foundation

/// Main API for the AI-powered news companion.
public enum NewsCompanionKit {

    public struct Config: Sendable {
        public var apiKey: String
        public var articleFetcher: (any ArticleFetching)?
        public var timeout: TimeInterval
        public var maxArticleLength: Int

        public init(apiKey: String, articleFetcher: (any ArticleFetching)? = nil, timeout: TimeInterval = 25, maxArticleLength: Int = 12_000) {
            self.apiKey = apiKey
            self.articleFetcher = articleFetcher
            self.timeout = timeout
            self.maxArticleLength = maxArticleLength
        }
    }

    /// Generates companion insights for the article at the given URL. Use the returned result to render the companion sheet.
    /// - Parameters:
    ///   - url: Article URL.
    ///   - config: Configuration including API key (supply key when ready).
    /// - Returns: Structured companion result, or throws on fetch/AI failure.
    public static func generate(url: URL, config: Config) async throws -> CompanionResult {
        let fetcher: any ArticleFetching = config.articleFetcher ?? ArticleFetcher(config: .init(maxArticleLength: config.maxArticleLength))
        let article = try await fetcher.fetch(url: url)
        guard !article.text.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NewsCompanionKitError.emptyArticle
        }
        let aiClient = GeminiClient(apiKey: config.apiKey, timeout: config.timeout)
        let engine = ConversationEngine(aiClient: aiClient, maxArticleChars: config.maxArticleLength)
        return try await engine.generate(article: article)
    }
}

public enum NewsCompanionKitError: Error {
    case emptyArticle
}
