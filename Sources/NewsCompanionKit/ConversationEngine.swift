import Foundation

/// Converts article content into structured companion insights via the AI client.
public final class ConversationEngine: Sendable {

    private let aiClient: any AICompleting
    private let maxArticleChars: Int

    public init(aiClient: any AICompleting, maxArticleChars: Int = 12_000) {
        self.aiClient = aiClient
        self.maxArticleChars = maxArticleChars
    }

    public func generate(article: ArticleContent) async throws -> CompanionResult {
        let trimmedText = String(article.text.prefix(maxArticleChars))
        let prompt = buildPrompt(title: article.title, text: trimmedText)
        var raw: String
        do {
            raw = try await aiClient.complete(prompt: prompt)
        } catch {
            throw ConversationEngineError.aiFailed(error)
        }
        if let result = parseResponse(raw) { return result }
        // Retry once with stricter instruction
        let retryPrompt = prompt + "\n\nImportant: Return valid JSON only, no markdown or extra text."
        do {
            raw = try await aiClient.complete(prompt: retryPrompt)
        } catch {
            throw ConversationEngineError.aiFailed(error)
        }
        if let result = parseResponse(raw) { return result }
        throw ConversationEngineError.invalidJSON
    }

    private func buildPrompt(title: String, text: String) -> String {
        """
        You are a news companion. Based on the following article, return a single JSON object with this exact structure. Use only the keys below. No markdown, no code fence.

        {
          "summary": {
            "oneLiner": "One sentence summary",
            "bullets": ["Bullet 1", "Bullet 2", "Bullet 3"],
            "whyItMatters": "One short paragraph on why this story matters"
          },
          "topics": [
            { "title": "Short topic label", "prompt": "Question or instruction for follow-up" }
          ],
          "factChecks": [
            { "claim": "A specific claim from the article", "whatToVerify": "How to verify it" }
          ]
        }

        Rules:
        - summary.oneLiner: one clear sentence.
        - summary.bullets: 3 to 5 short bullet points.
        - summary.whyItMatters: 2-4 sentences max.
        - topics: 5 to 6 items. Use varied angles: what happens next, key players, why it matters to me, uncertainties, for vs against, timeline, what to watch.
        - factChecks: 0 to 3 items. Only include if the article makes verifiable claims worth checking.

        Article title: \(title)

        Article text:
        \(text)
        """
    }

    private func parseResponse(_ raw: String) -> CompanionResult? {
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
        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIResponse.self, from: data) else { return nil }
        return decoded.toCompanionResult()
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
    }
    struct FactCheckPart: Decodable {
        let claim: String?
        let whatToVerify: String?
    }

    func toCompanionResult() -> CompanionResult {
        let s = summary ?? AIResponse.SummaryPart(oneLiner: nil, bullets: nil, whyItMatters: nil)
        let oneLiner = s.oneLiner?.trimmingCharacters(in: .whitespaces) ?? "No summary available."
        let bullets = (s.bullets ?? []).compactMap { b in
            let t = b.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        let whyItMatters = s.whyItMatters?.trimmingCharacters(in: .whitespaces) ?? ""
        let summaryModel = Summary(oneLiner: oneLiner, bullets: bullets, whyItMatters: whyItMatters)

        let topicChips = (topics ?? []).compactMap { t -> TopicChip? in
            guard let title = t.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty,
                  let prompt = t.prompt?.trimmingCharacters(in: .whitespaces), !prompt.isEmpty else { return nil }
            return TopicChip(title: title, prompt: prompt)
        }

        let factChecksModel = (factChecks ?? []).compactMap { f -> FactCheck? in
            guard let claim = f.claim?.trimmingCharacters(in: .whitespaces), !claim.isEmpty,
                  let what = f.whatToVerify?.trimmingCharacters(in: .whitespaces), !what.isEmpty else { return nil }
            return FactCheck(claim: claim, whatToVerify: what)
        }

        return CompanionResult(summary: summaryModel, topics: Array(topicChips.prefix(6)), factChecks: factChecksModel)
    }
}

public enum ConversationEngineError: Error {
    case aiFailed(Error)
    case invalidJSON
}
