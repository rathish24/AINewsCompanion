import Foundation

// MARK: - TextTranslating

/// Protocol for translating text from a source language to a target language (e.g. English → Tamil).
public protocol TextTranslating: Sendable {
    /// Translates the given text from the source language to the target language.
    /// - Parameters:
    ///   - text: Text to translate.
    ///   - sourceLanguageCode: BCP-47 or ISO 639-1 source code (e.g. `"en"`). Use `"auto"` for auto-detect when supported.
    ///   - targetLanguageCode: BCP-47 or ISO 639-1 target code (e.g. `"ta"` for Tamil).
    /// - Returns: The translated text.
    func translate(
        text: String,
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) async throws -> String
}

// MARK: - Translation Client Error

public enum TranslationClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid translation API URL"
        case .invalidResponse: return "Invalid response from translation API"
        case .apiError(let msg): return msg
        }
    }
}
