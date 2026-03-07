import Foundation
import Testing
@testable import NewsCompanionKit

@Suite("Conversation Engine Tests")
struct ConversationEngineTests {

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

        let firstTopic = try #require(result.topics.first)
        let parsedSummary = try #require(firstTopic.summary)

        #expect(parsedSummary == summary)
        #expect(parsedSummary.count > 100)
        #expect(parsedSummary.contains("It also highlights"))
    }
}

private struct MockAICompleter: AICompleting {
    let response: String

    func complete(prompt: String) async throws -> String {
        response
    }
}
