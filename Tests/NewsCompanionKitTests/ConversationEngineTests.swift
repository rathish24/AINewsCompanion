import Foundation
import Testing
@testable import NewsCompanionKit

@Suite("Conversation Engine Tests")
struct ConversationEngineTests {

    @Test("Bundled conversation.json and topics.json load and are valid")
    func bundledConfigsLoad() {
        let promptConfig = ConversationPromptConfig.loadBundled()
        #expect(!promptConfig.intro.isEmpty)
        #expect(!promptConfig.rules.isEmpty)
        #expect(!promptConfig.jsonStructure.isEmpty)
        #expect(!promptConfig.articleTitleLabel.isEmpty)
        #expect(!promptConfig.articleTextLabel.isEmpty)
        #expect(!promptConfig.retrySuffix.isEmpty)

        let topicConfig = TopicValidator.loadBundledConfig()
        #expect(!topicConfig.fillerPhrases.isEmpty)
        #expect(!topicConfig.fillerTitles.isEmpty)
        #expect(!topicConfig.angles.isEmpty)
        #expect(!topicConfig.validation.groundingKeywords.isEmpty)
    }

    @Test("Multi-sentence topic summary is preserved without truncation")
    func preservesTopicSummary() async throws {
        let summary = """
        This topic explains what happens next in the regulatory process and why the timeline may slip further. It also highlights which agencies and companies are likely to shape the next decision.
        """

        let json = """
        {
          "summary": {
            "oneLiner": "The regulator delayed a decision on the merger.",
            "bullets": ["A formal review is ongoing.", "The companies must answer more questions.", "Investors are watching the timetable."],
            "whyItMatters": "The decision could reshape competition in the sector."
          },
          "topics": [
            {
              "title": "What happens next",
              "prompt": "Based on the article, what are the most likely next developments in the review process?",
              "summary": "\(summary)"
            }
          ],
          "factChecks": []
        }
        """

        let engine = ConversationEngine(aiClient: MockAICompleter(response: json))
        let result = try await engine.generate(article: .init(title: "Merger review delayed", text: "Article body"))

        let matchedTopic = try #require(result.topics.first(where: { $0.title == "What happens next" }))
        let parsedSummary = try #require(matchedTopic.summary)

        #expect(parsedSummary == summary)
        #expect(parsedSummary.count > 100)
        #expect(parsedSummary.contains("It also highlights"))
    }

    @Test("Full companion JSON (conversation.json structure) produces valid CompanionResult with 5 topics and factChecks")
    func fullCompanionJSONProducesCorrectStructure() async throws {
        let fullJSON = """
        {
          "summary": {
            "oneLiner": "US and Israel conducted strikes; Iran and allies responded.",
            "bullets": [
              "Strikes targeted specific sites.",
              "Strategy aims to deter escalation.",
              "International reaction is mixed."
            ],
            "whyItMatters": "The situation affects regional stability and global security."
          },
          "topics": [
            { "title": "What happened", "prompt": "Based on the article, what did the US and Israel strikes do?", "summary": "The article describes the strikes and their stated aims." },
            { "title": "Why it matters", "prompt": "Based on the article, why do these strikes matter?", "summary": "Regional stability and deterrence are at stake." },
            { "title": "What happens next", "prompt": "Based on the article, what are likely next steps?", "summary": "The article outlines possible escalation or de-escalation paths." },
            { "title": "Key players", "prompt": "Who are the main actors in the article?", "summary": "US, Israel, Iran and allied groups are named." },
            { "title": "Biggest unknowns", "prompt": "What remains unclear from the article?", "summary": "Exact casualty figures and long-term impact are uncertain." }
          ],
          "factChecks": [
            { "claim": "The strikes were coordinated.", "whatToVerify": "Check official statements for timing and coordination." }
          ]
        }
        """
        let engine = ConversationEngine(aiClient: MockAICompleter(response: fullJSON))
        let result = try await engine.generate(article: .init(title: "Iran war strategy", text: "Article text about US and Israel strikes."))

        #expect(!result.summary.oneLiner.isEmpty)
        #expect(result.summary.bullets.count == 3)
        #expect(!result.summary.whyItMatters.isEmpty)
        #expect(result.topics.count == 5)
        #expect(result.factChecks.count == 1)
        #expect(result.topics.contains(where: { $0.title == "What happened" }))
        #expect(result.topics.contains(where: { $0.title == "Key players" }))
        #expect(result.factChecks.first?.claim == "The strikes were coordinated.")
    }

    @Test("Azure-style response with top-level \"final\" JSON string is unwrapped and parsed correctly")
    func azureFinalWrapperParsedCorrectly() async throws {
        // Some Azure models return {"final": "<escaped JSON string>"}. Inner JSON must be parsed.
        let innerJSON = """
        {"summary":{"oneLiner":"McLaren locked out the front row.","bullets":["Norris on pole.","Piastri second."],"whyItMatters":"Strong position for the race."},"topics":[{"title":"Pole result","prompt":"Who took pole?","summary":"Norris took pole."}],"factChecks":[{"claim":"McLaren were favourites","whatToVerify":"Check pre-season predictions."}]}
        """
        let wrapper: [String: String] = ["final": innerJSON]
        let wrapped = String(data: try JSONEncoder().encode(wrapper), encoding: .utf8)!
        let engine = ConversationEngine(aiClient: MockAICompleter(response: wrapped))
        let result = try await engine.generate(article: .init(title: "Australian GP", text: "Qualifying report."))

        #expect(result.summary.oneLiner == "McLaren locked out the front row.")
        #expect(result.summary.bullets.count == 2)
        #expect(!result.summary.whyItMatters.isEmpty)
        #expect(result.factChecks.count == 1)
        #expect(result.factChecks.first?.claim == "McLaren were favourites")
        // Topics may be 0 after TopicValidator filtering; the important part is that inner JSON was unwrapped and parsed
    }

    // MARK: - First load from API (e.g. Azure), second load from cache (e.g. SwiftData)

    @Test("resultFetcher: first call uses generate (API path), second call returns from cache without calling generate")
    func resultFetcherFirstLoadFromAPISecondFromCache() async throws {
        let url = URL(string: "https://example.com/article")!
        let sampleResult = CompanionResult(
            summary: Summary(oneLiner: "Cached one-liner.", bullets: ["A.", "B."], whyItMatters: "Matters."),
            topics: [TopicChip(title: "What happened", prompt: "What happened?", summary: "Summary.")],
            factChecks: []
        )
        let cache = MockCompanionResultCache()
        let generateCallCount = _Box(0)
        let config = NewsCompanionKit.Config(apiKey: "key", provider: .azureOpenAI, model: "gpt-4o-mini", azureEndpoint: "https://test.openai.azure.com")
        let fetcher = NewsCompanionKit.resultFetcher(config: config, cache: cache, generateOverride: { _ in
            generateCallCount.value += 1
            return sampleResult
        })

        let first = try await fetcher(url)
        #expect(generateCallCount.value == 1)
        #expect(first.summary.oneLiner == "Cached one-liner.")

        let second = try await fetcher(url)
        #expect(generateCallCount.value == 1, "Second call must not invoke generate; result must come from cache")
        #expect(second.summary.oneLiner == "Cached one-liner.")
        #expect(second.topics.count == first.topics.count)
    }

    @Test("CompanionResult round-trips through JSON encode/decode (same as SwiftData persistence)")
    func companionResultRoundTripsThroughJSON() throws {
        let result = CompanionResult(
            summary: Summary(oneLiner: "One.", bullets: ["B1.", "B2."], whyItMatters: "Why."),
            topics: [
                TopicChip(title: "What happened", prompt: "What happened?", summary: "S1."),
                TopicChip(title: "Key players", prompt: "Who?", summary: "S2."),
            ],
            factChecks: [FactCheck(claim: "Claim.", whatToVerify: "Verify.")]
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CompanionResult.self, from: data)
        #expect(decoded.summary.oneLiner == result.summary.oneLiner)
        #expect(decoded.summary.bullets == result.summary.bullets)
        #expect(decoded.topics.count == result.topics.count)
        #expect(decoded.factChecks.count == result.factChecks.count)
        #expect(decoded.factChecks.first?.claim == result.factChecks.first?.claim)
        #expect(decoded.textForSpeech == result.textForSpeech)
    }
}

private final class _Box<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class MockCompanionResultCache: NewsCompanionKit.CompanionResultCaching {
    private var storage: [URL: CompanionResult] = [:]

    func cachedResult(for url: URL) async -> CompanionResult? {
        storage[url]
    }

    func save(result: CompanionResult, for url: URL) async {
        storage[url] = result
    }
}

private struct MockAICompleter: AICompleting {
    let response: String

    func complete(prompt: String) async throws -> String {
        response
    }
}
