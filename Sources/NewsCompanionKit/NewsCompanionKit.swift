import Foundation

// MARK: - AI Provider

public enum AIProvider: String, CaseIterable, Sendable, Codable {
    case gemini
    case claude
    case openAI
    case groq
    case huggingFace

    public var displayName: String {
        switch self {
        case .gemini:      return "Gemini"
        case .claude:      return "Claude"
        case .openAI:      return "OpenAI"
        case .groq:        return "Groq"
        case .huggingFace: return "Hugging Face"
        }
    }
}

/// Main API for the AI-powered news companion.
public enum NewsCompanionKit {

    public struct Config: Sendable {
        public var apiKey: String
        public var provider: AIProvider
        public var model: String?
        public var articleFetcher: (any ArticleFetching)?
        public var timeout: TimeInterval
        public var maxArticleLength: Int
        public var debugLog: (@Sendable (String) -> Void)?

        public init(
            apiKey: String,
            provider: AIProvider = .groq,
            model: String? = nil,
            articleFetcher: (any ArticleFetching)? = nil,
            timeout: TimeInterval = 60,
            maxArticleLength: Int = 12_000,
            debugLog: (@Sendable (String) -> Void)? = nil
        ) {
            self.apiKey = apiKey
            self.provider = provider
            self.model = model
            self.articleFetcher = articleFetcher
            self.timeout = timeout
            self.maxArticleLength = maxArticleLength
            self.debugLog = debugLog
        }
    }

    /// Creates the appropriate AI client for the configured provider.
    static func makeAIClient(config: Config) -> any AICompleting {
        switch config.provider {
        case .gemini:
            return GeminiClient(
                apiKey: config.apiKey,
                model: config.model ?? "gemini-2.0-flash",
                timeout: config.timeout
            )
        case .claude:
            return ClaudeClient(
                apiKey: config.apiKey,
                model: config.model ?? "claude-sonnet-4-20250514",
                timeout: config.timeout
            )
        case .openAI:
            return OpenAIClient(
                apiKey: config.apiKey,
                model: config.model ?? "gpt-4o-mini",
                timeout: config.timeout
            )
        case .groq:
            return GroqClient(
                apiKey: config.apiKey,
                model: config.model ?? "llama-3.1-8b-instant",
                timeout: config.timeout
            )
        case .huggingFace:
            return HuggingFaceClient(
                apiKey: config.apiKey,
                model: config.model ?? "mistralai/Mistral-7B-Instruct-v0.3",
                timeout: config.timeout
            )
        }
    }

    /// Translates English text to the target language using the configured AI provider. Use for TTS when the target language is not English.
    public static func translate(text: String, targetLanguageCode: String, targetLanguageName: String, config: Config) async throws -> String {
        let prompt = """
        You are a translator. Translate the following English text into \(targetLanguageName). Output only the \(targetLanguageName) translation, nothing else: no quotes, no "Translation:", no explanation.

        Text to translate:
        \(text)
        """
        let client = makeAIClient(config: config)
        let result = try await client.complete(prompt: prompt)
        var translated = result.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Translation:", "Here is the translation:", "Here's the translation:", "\(targetLanguageName) translation:"] {
            if translated.lowercased().hasPrefix(prefix.lowercased()) {
                translated = String(translated.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return translated
    }

    public static func generate(url: URL, config: Config) async throws -> CompanionResult {
        do {
            config.debugLog?("[\(config.provider.displayName)] request starting – url: \(url.absoluteString)")
            let fetcher: any ArticleFetching = config.articleFetcher ?? ArticleFetcher(config: .init(maxArticleLength: config.maxArticleLength))
            let article = try await fetcher.fetch(url: url)
            config.debugLog?("Article fetched – title: \(article.title.prefix(60))...")
            guard !article.text.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NewsCompanionKitError.emptyArticle
            }
            config.debugLog?("Calling \(config.provider.displayName) (\(config.model ?? "default model"))...")
            let aiClient = makeAIClient(config: config)
            let engine = ConversationEngine(aiClient: aiClient, maxArticleChars: config.maxArticleLength)
            let result = try await engine.generate(article: article)
            config.debugLog?("[\(config.provider.displayName)] response OK – oneLiner: \(result.summary.oneLiner.prefix(80))...")
            return result
        } catch {
            config.debugLog?("[\(config.provider.displayName)] failed – \(error.localizedDescription)")
            throw error
        }
    }
}

public enum NewsCompanionKitError: Error {
    case emptyArticle
}
