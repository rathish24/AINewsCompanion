import Foundation

// MARK: - Conversation prompt config (decoded from conversation.json or future API)

public struct ConversationPromptConfig: Codable, Sendable {
    let intro: String
    let jsonStructure: String
    let rules: [String]
    let articleTitleLabel: String
    let articleTextLabel: String
    let retrySuffix: String

    static func loadBundled() -> ConversationPromptConfig {
        guard let url = Bundle.module.url(forResource: "conversation", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(ConversationPromptConfig.self, from: data) else {
            fatalError("conversation.json missing or invalid in NewsCompanionKit bundle")
        }
        return config
    }

    static func config(from jsonData: Data) throws -> ConversationPromptConfig {
        try JSONDecoder().decode(ConversationPromptConfig.self, from: jsonData)
    }
}

// MARK: - Conversation Engine

/// Converts article content into structured companion insights via the AI client.
/// Prompt rules come from conversation.json; topic validation from topics.json (single responsibility).
public final class ConversationEngine: Sendable {

    private let aiClient: any AICompleting
    private let maxArticleChars: Int
    private let promptConfig: ConversationPromptConfig?
    private let topicConfig: TopicValidatorConfig?

    public init(
        aiClient: any AICompleting,
        maxArticleChars: Int = 12_000,
        promptConfig: ConversationPromptConfig? = nil,
        topicConfig: TopicValidatorConfig? = nil
    ) {
        self.aiClient = aiClient
        self.maxArticleChars = maxArticleChars
        self.promptConfig = promptConfig
        self.topicConfig = topicConfig
    }

    public func generate(article: ArticleContent) async throws -> CompanionResult {
        let trimmedText = String(article.text.prefix(maxArticleChars))
        let effectivePromptConfig = promptConfig ?? ConversationPromptConfig.loadBundled()
        let effectiveTopicConfig = topicConfig ?? TopicValidator.loadBundledConfig()
        let prompt = buildPrompt(title: article.title, text: trimmedText, config: effectivePromptConfig)
        
        print("[ConversationEngine] generate – promptLength: \(prompt.count)")
        var raw: String
        do {
            raw = try await aiClient.complete(prompt: prompt)
            print("[ConversationEngine] aiClient.complete (first) – responseLength: \(raw.count)")
        } catch {
            print("[ConversationEngine] aiClient.complete (first) failed – \(error.localizedDescription)")
            throw ConversationEngineError.aiFailed(error)
        }
        if let result = parseResponse(raw, config: effectiveTopicConfig) {
            print("[ConversationEngine] parseResponse success (first)")
            return result
        }
        print("[ConversationEngine] parseResponse failed, retrying with retrySuffix")
        let retryPrompt = prompt + "\n\n" + effectivePromptConfig.retrySuffix
        do {
            raw = try await aiClient.complete(prompt: retryPrompt)
            print("[ConversationEngine] aiClient.complete (retry) – responseLength: \(raw.count)")
        } catch {
            print("[ConversationEngine] aiClient.complete (retry) failed – \(error.localizedDescription)")
            throw ConversationEngineError.aiFailed(error)
        }
        if let result = parseResponse(raw, config: effectiveTopicConfig) {
            print("[ConversationEngine] parseResponse success (retry)")
            return result
        }
        print("[ConversationEngine] parseResponse failed – invalidJSON")
        throw ConversationEngineError.invalidJSON
    }

    private func buildPrompt(title: String, text: String, config: ConversationPromptConfig) -> String {
        let rulesBlock = config.rules.map { "- \($0)" }.joined(separator: "\n")
        return """
        \(config.intro)

        \(config.jsonStructure)

        Rules:
        \(rulesBlock)

        \(config.articleTitleLabel) \(title)

        \(config.articleTextLabel)
        \(text)
        """
    }

    private func parseResponse(_ raw: String, config: TopicValidatorConfig) -> CompanionResult? {
        var cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Extract JSON object if there is preamble or trailing text (e.g. "Here is the JSON:\n{...}")
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8) else { return nil }

        // If top-level looks like direct payload (has "summary" or "topics"), decode as AIResponse first.
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           dict["summary"] != nil || dict["topics"] != nil {
            if let decoded = try? JSONDecoder().decode(AIResponse.self, from: data),
               let result = decoded.toCompanionResultIfNonEmpty(config: config) {
                return result
            }
        }

        // Some models (e.g. Azure) wrap payload in a string under "final", "content", "result", etc.
        let wrapperKeys = ["final", "content", "result", "response", "data", "output", "text"]
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let innerString = wrapperKeys.lazy
            .compactMap { dict[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        if let inner = innerString {
            // Try decode inner as JSON (AIResponse)
            var innerData = inner.data(using: .utf8)
            if innerData == nil, inner.first == "{", inner.contains("\\\"") {
                // Possibly double-escaped: replace \" with " for one more level
                let unescaped = inner.replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
                innerData = unescaped.data(using: .utf8)
            }
            if let data = innerData,
               let decoded = try? JSONDecoder().decode(AIResponse.self, from: data),
               let result = decoded.toCompanionResultIfNonEmpty(config: config) {
                return result
            }
            // We had a wrapper with content but inner failed to parse → do not fall back to outer; fail so engine retries
            return nil
        }

        // Direct decode when no wrapper detected
        guard let decoded = try? JSONDecoder().decode(AIResponse.self, from: data),
              let result = decoded.toCompanionResultIfNonEmpty(config: config) else { return nil }
        return result
    }
}

private struct AIResponse: Decodable {
    let summary: SummaryPart?
    let topics: [TopicPart]?
    let factChecks: [FactCheckPart]?

    struct SummaryPart: Decodable {
        let oneLiner: String?
        let bullets: [String]?
        let whyItMatters: String?
    }
    struct TopicPart: Decodable {
        let title: String?
        let prompt: String?
        let summary: String?
    }
    struct FactCheckPart: Decodable {
        let claim: String?
        let whatToVerify: String?
    }

    /// Returns a valid companion result, or nil if the decoded payload is effectively empty (so caller can treat as parse failure and retry).
    func toCompanionResultIfNonEmpty(config: TopicValidatorConfig) -> CompanionResult? {
        let result = toCompanionResult(config: config)
        let emptyOneLiner = result.summary.oneLiner.isEmpty || result.summary.oneLiner == "No summary available."
        let noContent = emptyOneLiner && result.summary.bullets.isEmpty && result.summary.whyItMatters.isEmpty && result.topics.isEmpty && result.factChecks.isEmpty
        if noContent { return nil }
        return result
    }

    func toCompanionResult(config: TopicValidatorConfig) -> CompanionResult {
        let s = summary ?? AIResponse.SummaryPart(oneLiner: nil, bullets: nil, whyItMatters: nil)
        let oneLiner = s.oneLiner?.trimmingCharacters(in: .whitespaces) ?? "No summary available."
        let bullets = (s.bullets ?? []).compactMap { b in
            let t = b.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        let whyItMatters = s.whyItMatters?.trimmingCharacters(in: .whitespaces) ?? ""
        let summaryModel = Summary(oneLiner: oneLiner, bullets: bullets, whyItMatters: whyItMatters)

        // Parse raw chips, normalize whitespace, basic dedup
        var seenTopicKeys = Set<String>()
        let rawChips = (topics ?? []).compactMap { t -> TopicChip? in
            guard let rawTitle = t.title?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty,
                  let rawPrompt = t.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPrompt.isEmpty else { return nil }
            let title = rawTitle.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let prompt = rawPrompt.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let trimmedSummary = t.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary: String? = (trimmedSummary?.isEmpty == false) ? trimmedSummary : nil
            let dedupeKey = "\(title.lowercased())|\(prompt.lowercased())"
            guard !seenTopicKeys.contains(dedupeKey) else { return nil }
            seenTopicKeys.insert(dedupeKey)
            return TopicChip(title: title, prompt: prompt, summary: summary)
        }

        // Full pipeline: validate → angle dedupe → score → order → return up to 5 valid topics
        let validatedTopics = TopicValidator.process(raw: rawChips, articleTitle: oneLiner, config: config)

        let factChecksModel = (factChecks ?? []).compactMap { f -> FactCheck? in
            guard let claim = f.claim?.trimmingCharacters(in: .whitespaces), !claim.isEmpty,
                  let what = f.whatToVerify?.trimmingCharacters(in: .whitespaces), !what.isEmpty else { return nil }
            return FactCheck(claim: claim, whatToVerify: what)
        }
        print("[ConversationEngine] parseResponse – summary: \(summaryModel), topics: \(validatedTopics), factChecks: \(factChecksModel)")
        return CompanionResult(summary: summaryModel, topics: validatedTopics, factChecks: factChecksModel)
    }
}

public enum ConversationEngineError: Error {
    case aiFailed(Error)
    case invalidJSON
}
