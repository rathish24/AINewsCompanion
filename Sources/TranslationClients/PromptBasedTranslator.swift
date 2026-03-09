import Foundation

/// Completer used for prompt-based translation (e.g. AWS Bedrock, Azure OpenAI, Google Vertex). Same signature as `AICompleting.complete(prompt:)` so you can pass any such client.
public protocol TranslationPromptCompleting: Sendable {
    func complete(prompt: String) async throws -> String
}

/// Drop-in wrapper that turns any `complete(prompt:)`-style closure or client into `TranslationPromptCompleting`. Use with NewsCompanionKit’s Bedrock/Azure/Vertex client: `ClosureTranslationPromptCompleter { try await myAIClient.complete(prompt: $0) }`.
public struct ClosureTranslationPromptCompleter: TranslationPromptCompleting, Sendable {
    private let _complete: @Sendable (String) async throws -> String

    public init(complete: @escaping @Sendable (String) async throws -> String) {
        _complete = complete
    }

    public func complete(prompt: String) async throws -> String {
        try await _complete(prompt)
    }
}

/// Translates text using an LLM and the prompt from translation.json. Use with AWS Bedrock, Azure OpenAI, or Google Vertex for production-grade, instruction-following translation.
/// The prompt is loaded from translation.json at the start of each `translate()` call.
public final class PromptBasedTranslator: TextTranslating, Sendable {

    private let completer: any TranslationPromptCompleting

    /// Creates a translator that loads translation.json at the start of each translate() call.
    public init(completer: any TranslationPromptCompleting) {
        self.completer = completer
    }

    /// Creates a translator with a preloaded model (e.g. for tests with a custom bundle). translate() still loads fresh from the default bundle each time unless you use this with a test bundle.
    public init(promptModel: TranslationPromptModel, completer: any TranslationPromptCompleting) {
        self.completer = completer
    }

    /// Loads the default prompt from translation.json in the module bundle. Returns nil if the resource is missing or invalid.
    /// Pass a bundle to load from a custom bundle (e.g. tests).
    public static func loadPromptModel(from bundle: Bundle? = nil) -> TranslationPromptModel? {
        let b = bundle ?? Bundle.module
        guard let url = b.url(forResource: "translation", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TranslationPromptModel.self, from: data)
    }

    public func translate(
        text: String,
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) async throws -> String {
        try await translate(
            text: text,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            targetLocale: "",
            contentType: "general"
        )
    }

    /// Translates with optional locale and content type (for the prompt). Loads translation.json at the start of each call.
    public func translate(
        text: String,
        sourceLanguageCode: String,
        targetLanguageCode: String,
        targetLocale: String,
        contentType: String
    ) async throws -> String {
        guard let loadedModel = Self.loadPromptModel() else {
            throw TranslationClientError.apiError("Translation prompt (translation.json) could not be loaded")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let inputJSON: [String: String] = [
            "source_language": sourceLanguageCode.isEmpty ? "English" : sourceLanguageCode,
            "target_language": targetLanguageCode,
            "target_locale": targetLocale,
            "content_type": contentType,
            "text": trimmed
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputJSON),
              let inputString = String(data: inputData, encoding: .utf8) else {
            throw TranslationClientError.apiError("Failed to build input JSON")
        }

        let prompt = loadedModel.instruction + "\n\nInput JSON:\n" + inputString

        let response = try await completer.complete(prompt: prompt)
        return try parseTranslatedText(from: response, outputKey: loadedModel.outputKey)
    }

    private func parseTranslatedText(from response: String, outputKey: String) throws -> String {
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = Self.extractJSON(from: cleaned)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translated = json[outputKey] as? String else {
            throw TranslationClientError.invalidResponse
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips markdown code fences (e.g. ```json ... ```) so we can parse JSON from LLM output.
    private static func extractJSON(from raw: String) -> String {
        var s = raw
        let patterns = ["```json", "```JSON", "```"]
        for prefix in patterns {
            if let start = s.range(of: prefix) {
                s = String(s[start.upperBound..<s.endIndex])
                break
            }
        }
        if let end = s.range(of: "```") {
            s = String(s[s.startIndex..<end.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
