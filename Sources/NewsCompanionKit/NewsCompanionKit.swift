import Foundation

// MARK: - AI Provider

public enum AIProvider: String, CaseIterable, Sendable, Codable {
    case gemini
    case claude
    case openAI
    case groq
    case huggingFace
    case azureOpenAI
    case awsBedrock
    case googleCloudVertex

    public var displayName: String {
        switch self {
        case .gemini:           return "Gemini"
        case .claude:           return "Claude"
        case .openAI:           return "OpenAI"
        case .groq:             return "Groq"
        case .huggingFace:      return "Hugging Face"
        case .azureOpenAI:      return "Azure OpenAI"
        case .awsBedrock:       return "AWS Bedrock"
        case .googleCloudVertex: return "Google Cloud Vertex"
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

        /// Azure OpenAI: resource base URL (e.g. `https://your-resource.openai.azure.com`). Required when `provider == .azureOpenAI`. `model` is the deployment name.
        public var azureEndpoint: String?
        /// AWS: region (e.g. `us-east-1`) or use `awsEndpoint` for a custom proxy URL. `model` is the Bedrock model ID.
        public var awsRegion: String?
        /// AWS: optional full endpoint URL (e.g. proxy). When set, overrides URL built from `awsRegion`.
        public var awsEndpoint: String?
        /// Google Cloud Vertex: project ID. Required when `provider == .googleCloudVertex`.
        public var gcpProject: String?
        /// Google Cloud Vertex: location (e.g. `us-central1`). Required when `provider == .googleCloudVertex`. `model` is the model name (e.g. `gemini-1.5-flash`).
        public var gcpLocation: String?
        /// Optional extra HTTP headers for cloud clients (Azure, AWS, Google). Use when your endpoint requires custom headers (e.g. tenant ID, tracing).
        public var additionalHeaders: [String: String]?

        public init(
            apiKey: String,
            provider: AIProvider = .groq,
            model: String? = nil,
            articleFetcher: (any ArticleFetching)? = nil,
            timeout: TimeInterval = 60,
            maxArticleLength: Int = 12_000,
            debugLog: (@Sendable (String) -> Void)? = nil,
            azureEndpoint: String? = nil,
            awsRegion: String? = nil,
            awsEndpoint: String? = nil,
            gcpProject: String? = nil,
            gcpLocation: String? = nil,
            additionalHeaders: [String: String]? = nil
        ) {
            self.apiKey = apiKey
            self.provider = provider
            self.model = model
            self.articleFetcher = articleFetcher
            self.timeout = timeout
            self.maxArticleLength = maxArticleLength
            self.debugLog = debugLog
            self.azureEndpoint = azureEndpoint
            self.awsRegion = awsRegion
            self.awsEndpoint = awsEndpoint
            self.gcpProject = gcpProject
            self.gcpLocation = gcpLocation
            self.additionalHeaders = additionalHeaders
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
        case .azureOpenAI:
            let endpoint = config.azureEndpoint ?? ""
            let deployment = config.model ?? "gpt-4o-mini"
            return AzureOpenAIClient(endpoint: endpoint, deployment: deployment, apiKey: config.apiKey, timeout: config.timeout, additionalHeaders: config.additionalHeaders)
        case .awsBedrock:
            let endpoint: String
            if let custom = config.awsEndpoint, !custom.isEmpty {
                endpoint = custom
            } else if let region = config.awsRegion, !region.isEmpty {
                endpoint = "https://bedrock-runtime.\(region).amazonaws.com"
            } else {
                endpoint = "https://bedrock-runtime.us-east-1.amazonaws.com"
            }
            let modelId = config.model ?? "anthropic.claude-3-sonnet-20240229-v1:0"
            return AWSBedrockClient(endpoint: endpoint, modelId: modelId, apiKey: config.apiKey, timeout: config.timeout, additionalHeaders: config.additionalHeaders)
        case .googleCloudVertex:
            let project = config.gcpProject ?? ""
            let location = config.gcpLocation ?? "us-central1"
            let model = config.model ?? "gemini-1.5-flash"
            return GoogleCloudVertexClient(project: project, location: location, model: model, apiKey: config.apiKey, timeout: config.timeout, additionalHeaders: config.additionalHeaders)
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

    // MARK: - App 2 (audio-only, no sheet): result fetcher with optional cache

    /// Optional cache for companion results. Implement this (e.g. with SwiftData, UserDefaults, or in-memory) and pass to `resultFetcher(config:cache:)` so App 2 avoids refetching. Pass `nil` for no caching.
    public protocol CompanionResultCaching: AnyObject {
        func cachedResult(for url: URL) async -> CompanionResult?
        func save(result: CompanionResult, for url: URL) async
    }

    /// Returns a closure that fetches a companion result for a URL: uses cache when provided and returns a cached result when available, otherwise calls `generate(url:config:)` and optionally saves. Use in App 2: `let result = try await resultFetcher(config: config, cache: myCache)(url)` then `SummaryToAudio.shared.play(text: result.textForSpeech, ...)`.
    public static func resultFetcher(config: Config, cache: (any CompanionResultCaching)?) -> (URL) async throws -> CompanionResult {
        { url in
            if let cache = cache, let cached = await cache.cachedResult(for: url) {
                return cached
            }
            let result = try await generate(url: url, config: config)
            if let cache = cache {
                await cache.save(result: result, for: url)
            }
            return result
        }
    }
}

public enum NewsCompanionKitError: Error {
    case emptyArticle
}
