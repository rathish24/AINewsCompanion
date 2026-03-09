import Foundation

// MARK: - Translation Provider

public enum TranslationProvider: String, CaseIterable, Sendable, Codable {
    case aws
    case azure
    case googleCloud

    public var displayName: String {
        switch self {
        case .aws: return "AWS Translate"
        case .azure: return "Azure Translator"
        case .googleCloud: return "Google Cloud Translation"
        }
    }
}

// MARK: - Translation Config & Factory

/// Configuration for creating a translation client.
public struct TranslationConfig: Sendable {
    public var provider: TranslationProvider
    public var timeout: TimeInterval

    /// When true and `promptCompleter` is set, translation uses the prompt from translation.json via the given LLM (e.g. AWS Bedrock, Azure OpenAI, Vertex). Otherwise uses the provider’s native translation API.
    public var usePromptBasedTranslation: Bool
    /// LLM completer for prompt-based translation. Use a client that conforms to `TranslationPromptCompleting` (e.g. wrap your Bedrock/Azure/Vertex client).
    public var promptCompleter: (any TranslationPromptCompleting)?

    // AWS
    public var awsEndpoint: String?
    public var awsRegion: String?
    public var awsApiKey: String?
    public var awsAdditionalHeaders: [String: String]?

    // Azure
    public var azureEndpoint: String?
    public var azureSubscriptionKey: String?
    public var azureSubscriptionRegion: String?
    public var azureAdditionalHeaders: [String: String]?

    // Google Cloud
    public var googleApiKey: String?
    public var googleBaseURL: String?
    public var googleAdditionalHeaders: [String: String]?

    public init(
        provider: TranslationProvider,
        timeout: TimeInterval = 30,
        usePromptBasedTranslation: Bool = false,
        promptCompleter: (any TranslationPromptCompleting)? = nil,
        awsEndpoint: String? = nil,
        awsRegion: String? = nil,
        awsApiKey: String? = nil,
        awsAdditionalHeaders: [String: String]? = nil,
        azureEndpoint: String? = nil,
        azureSubscriptionKey: String? = nil,
        azureSubscriptionRegion: String? = nil,
        azureAdditionalHeaders: [String: String]? = nil,
        googleApiKey: String? = nil,
        googleBaseURL: String? = nil,
        googleAdditionalHeaders: [String: String]? = nil
    ) {
        self.provider = provider
        self.timeout = timeout
        self.usePromptBasedTranslation = usePromptBasedTranslation
        self.promptCompleter = promptCompleter
        self.awsEndpoint = awsEndpoint
        self.awsRegion = awsRegion
        self.awsApiKey = awsApiKey
        self.awsAdditionalHeaders = awsAdditionalHeaders
        self.azureEndpoint = azureEndpoint
        self.azureSubscriptionKey = azureSubscriptionKey
        self.azureSubscriptionRegion = azureSubscriptionRegion
        self.azureAdditionalHeaders = azureAdditionalHeaders
        self.googleApiKey = googleApiKey
        self.googleBaseURL = googleBaseURL
        self.googleAdditionalHeaders = googleAdditionalHeaders
    }
}

/// Factory and helpers for translation clients.
public enum TranslationClients {

    /// Creates the appropriate translation client for the configured provider. When `usePromptBasedTranslation` is true and `promptCompleter` is set, returns a translator that uses translation.json and the LLM; otherwise returns the native API client (AWS Translate, Azure Translator, Google Cloud Translation).
    public static func makeClient(config: TranslationConfig) -> any TextTranslating {
        if config.usePromptBasedTranslation, let completer = config.promptCompleter {
            return PromptBasedTranslator(completer: completer)
        }
        switch config.provider {
        case .aws:
            let endpoint: String
            if let custom = config.awsEndpoint, !custom.isEmpty {
                endpoint = custom
            } else if let region = config.awsRegion, !region.isEmpty {
                endpoint = "https://translate.\(region).amazonaws.com"
            } else {
                endpoint = "https://translate.us-east-1.amazonaws.com"
            }
            return AWSTranslateClient(
                endpoint: endpoint,
                apiKey: config.awsApiKey ?? "",
                timeout: config.timeout,
                additionalHeaders: config.awsAdditionalHeaders
            )
        case .azure:
            return AzureTranslatorClient(
                endpoint: config.azureEndpoint ?? "https://api.cognitive.microsofttranslator.com",
                subscriptionKey: config.azureSubscriptionKey ?? "",
                subscriptionRegion: config.azureSubscriptionRegion ?? "eastus",
                timeout: config.timeout,
                additionalHeaders: config.azureAdditionalHeaders
            )
        case .googleCloud:
            return GoogleCloudTranslateClient(
                apiKey: config.googleApiKey ?? "",
                timeout: config.timeout,
                baseURL: config.googleBaseURL ?? "https://translation.googleapis.com/language/translate/v2",
                additionalHeaders: config.googleAdditionalHeaders
            )
        }
    }

    /// Convenience: translate using a config (e.g. English → Tamil).
    public static func translate(
        text: String,
        sourceLanguageCode: String = "en",
        targetLanguageCode: String,
        config: TranslationConfig
    ) async throws -> String {
        let client = makeClient(config: config)
        return try await client.translate(
            text: text,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode
        )
    }
}
