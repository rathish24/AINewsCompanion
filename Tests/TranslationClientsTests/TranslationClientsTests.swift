import Foundation
import Testing
@testable import TranslationClients

@Suite("TranslationClients Tests")
struct TranslationClientsTests {

    @Test("Load prompt model from bundle returns valid model with output_key")
    func loadPromptModel() {
        let model = PromptBasedTranslator.loadPromptModel()
        #expect(model != nil)
        #expect(model?.outputKey == "translated_text")
        #expect(model?.instruction.isEmpty == false)
    }

    @Test("Prompt-based translator returns translated text from valid JSON response")
    func promptBasedTranslatorValidJSON() async throws {
        let model = try #require(PromptBasedTranslator.loadPromptModel())
        let mock = MockCompleter(response: #"{"translated_text": "வணக்கம்"}"#)
        let translator = PromptBasedTranslator(promptModel: model, completer: mock)
        let result = try await translator.translate(text: "Hello", sourceLanguageCode: "en", targetLanguageCode: "ta")
        #expect(result == "வணக்கம்")
    }

    @Test("Prompt-based translator parses JSON wrapped in markdown code fence")
    func promptBasedTranslatorMarkdownWrapped() async throws {
        let model = try #require(PromptBasedTranslator.loadPromptModel())
        let mock = MockCompleter(response: """
        ```json
        {"translated_text": "Bonjour"}
        ```
        """)
        let translator = PromptBasedTranslator(promptModel: model, completer: mock)
        let result = try await translator.translate(text: "Hello", sourceLanguageCode: "en", targetLanguageCode: "fr")
        #expect(result == "Bonjour")
    }

    @Test("Prompt-based translator returns empty string unchanged")
    func promptBasedTranslatorEmptyInput() async throws {
        let model = try #require(PromptBasedTranslator.loadPromptModel())
        let mock = MockCompleter(response: #"{"translated_text": ""}"#)
        let translator = PromptBasedTranslator(promptModel: model, completer: mock)
        let result = try await translator.translate(text: "   ", sourceLanguageCode: "en", targetLanguageCode: "ta")
        #expect(result == "   ")
    }

    @Test("MakeClient returns native client when usePromptBasedTranslation is false")
    func makeClientNative() {
        var config = TranslationConfig(provider: .googleCloud, googleApiKey: "test-key")
        config.usePromptBasedTranslation = false
        let client = TranslationClients.makeClient(config: config)
        #expect(client is GoogleCloudTranslateClient)
    }

    @Test("MakeClient returns PromptBasedTranslator when usePromptBasedTranslation true and completer set")
    func makeClientPromptBased() {
        var config = TranslationConfig(provider: .aws, promptCompleter: MockCompleter(response: "{}"))
        config.usePromptBasedTranslation = true
        let client = TranslationClients.makeClient(config: config)
        #expect(client is PromptBasedTranslator)
    }

    @Test("Chunking splits long text at word boundaries")
    func chunkingRespectsBoundaries() {
        let text = String(repeating: "word ", count: 2000)
        let chunks = TranslationChunking.chunks(for: text, maxCharacters: 5000)
        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.count <= 5000 })
        #expect(chunks.joined(separator: " ") == text.trimmingCharacters(in: .whitespaces))
    }

    @Test("Chunking by bytes keeps UTF-8 intact")
    func chunkingByBytes() {
        let text = "Hello world " + String(repeating: "x", count: 10000)
        let chunks = TranslationChunking.chunksByBytes(for: text, maxUTF8Bytes: 1000)
        #expect(chunks.count >= 2)
        let rejoined = chunks.joined()
        #expect(rejoined == text)
    }
}

private struct MockCompleter: TranslationPromptCompleting, Sendable {
    let response: String
    func complete(prompt: String) async throws -> String { response }
}
