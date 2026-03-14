import Foundation
import Testing
@testable import NewsCompanionKit

@Suite("Topic Validator Tests")
struct TopicValidatorTests {

    @Test("Validator returns up to 5 product-ready topics across article categories", arguments: ArticleFixture.allCases)
    func validatorProducesStrongTopicSets(for fixture: ArticleFixture) {
        let output = TopicValidator.process(
            raw: fixture.rawTopics,
            articleTitle: fixture.articleTitle
        )

        #expect(output.count >= 1)
        #expect(output.count <= 5)

        let lowerTitles = output.map { $0.title.lowercased() }
        #expect(!lowerTitles.contains("deep dive"))
        #expect(!lowerTitles.contains("more context"))
        #expect(!lowerTitles.contains("learn more"))

        let uniqueTitles = Set(lowerTitles)
        #expect(uniqueTitles.count == output.count)
    }

    @Test("Semantic duplicate angles keep only one best chip")
    func semanticDedupRemovesRepeatedAngles() {
        let rawTopics = [
            topic("What happens next", "Based on the article, what are the most likely next developments after the court ruling?"),
            topic("Next steps", "Based on the article, what comes next for the company after this earnings surprise?"),
            topic("Key players", "Who are the main people or organizations mentioned in the article and what are their roles?"),
            topic("Why it matters", "Based on the article, why does this story matter to everyday readers and markets?"),
            topic("Biggest unknowns", "What important questions remain unanswered based on the article and official statements?"),
            topic("What to watch", "Based on the article, what developments should readers monitor going forward?")
        ]

        let output = TopicValidator.process(raw: rawTopics, articleTitle: "Test article")
        let nextLikeTitles = output.filter {
            ["what happens next", "next steps", "what comes next"].contains($0.title.lowercased())
        }

        #expect(nextLikeTitles.count == 1)
    }

    @Test("Output is ordered by angle priority (details, players, timeline, next, … recap)")
    func outputRespectsAnglePriority() {
        let rawTopics = [
            topic("Key players", "Who are the main people or organizations mentioned in the article and what are their roles?"),
            topic("What happens next", "Based on the article, what are the most likely next developments after the ruling?"),
            topic("What happened", "Based on the article, what are the key events that occurred and led to this outcome?"),
            topic("Biggest unknowns", "What important questions remain unanswered based on the article and official statements?"),
            topic("Key details", "Based on the article, what evidence and numbers support the main claims?")
        ]

        let output = TopicValidator.process(raw: rawTopics, articleTitle: "Test ordering")

        #expect(output.count == 5)
        let titles = output.map { $0.title.lowercased() }
        // topics.json anglePriority: details, players, timeline, next, uncertainty, debate, recap, watchlist, other
        if let playersIdx = titles.firstIndex(where: { $0.contains("key players") }),
           let nextIdx = titles.firstIndex(where: { $0.contains("what happens next") }),
           let recapIdx = titles.firstIndex(where: { $0.contains("what happened") }) {
            #expect(playersIdx < nextIdx)
            #expect(nextIdx < recapIdx)
        }
    }

    @Test("When fewer than 5 valid topics, validator returns only those (no fallback fill)")
    func noFallbackWhenFewValidTopics() {
        let rawTopics = [
            topic("What happened", "Based on the article, what are the key events that occurred and why did they escalate?"),
            topic("Key players", "Who are the main people or organizations mentioned in the article and what are their roles?"),
            topic("Why it matters", "Based on the article, why does this story matter to everyday people and policymakers?")
        ]

        let output = TopicValidator.process(raw: rawTopics, articleTitle: "Short article")

        #expect(output.count == 3)
    }

    private static func topic(_ title: String, _ prompt: String) -> TopicChip {
        TopicChip(title: title, prompt: prompt)
    }

    private func topic(_ title: String, _ prompt: String) -> TopicChip {
        Self.topic(title, prompt)
    }
}

enum ArticleFixture: CaseIterable {
    case politics
    case business
    case technology
    case legal
    case health
    case breakingNews
    case narrowUpdate

    var articleTitle: String {
        switch self {
        case .politics:
            return "Senate leaders reach budget deal after weekend negotiations"
        case .business:
            return "Retail giant posts surprise profit as holiday sales rebound"
        case .technology:
            return "Chipmaker unveils new AI accelerator for data centers"
        case .legal:
            return "Court blocks merger pending antitrust review"
        case .health:
            return "Public health agency expands vaccine recommendation"
        case .breakingNews:
            return "Airport operations disrupted after overnight outage"
        case .narrowUpdate:
            return "City council delays vote on zoning change"
        }
    }

    var rawTopics: [TopicChip] {
        switch self {
        case .politics:
            return [
                .init(title: "What happened", prompt: "Based on the article, what are the key events that led to the budget deal announcement?"),
                .init(title: "Next steps", prompt: "Based on the article, what comes next for the budget package in Congress this week?"),
                .init(title: "Key players", prompt: "Who are the main lawmakers involved in the article and what positions are they taking?"),
                .init(title: "Why it matters", prompt: "Based on the article, why does this deal matter to agencies, voters, and federal funding?"),
                .init(title: "Biggest unknowns", prompt: "What important questions remain unanswered based on the article and the current compromise?"),
                .init(title: "Deep dive", prompt: "Learn more about the negotiations and background from this article.")
            ]
        case .business:
            return [
                .init(title: "What happened", prompt: "Based on the article, what drove the retailer's stronger than expected quarterly profit?"),
                .init(title: "Key players", prompt: "Who are the executives, analysts, or rivals mentioned in the article and why do they matter?"),
                .init(title: "Why it matters", prompt: "Based on the article, why does this earnings report matter to shoppers, staff, and investors?"),
                .init(title: "What to watch", prompt: "Based on the article, what signals should readers monitor in the retailer's next quarter?"),
                .init(title: "Biggest unknowns", prompt: "What important questions remain unanswered based on the article and management guidance?"),
                .init(title: "More context", prompt: "Find out more background and explore this topic in broader terms.")
            ]
        case .technology:
            return [
                .init(title: "What happened", prompt: "Based on the article, what did the chipmaker launch and how is it positioned against current rivals?"),
                .init(title: "Next steps", prompt: "Based on the article, what are the next milestones before customers can deploy this AI accelerator?"),
                .init(title: "Key players", prompt: "Who are the companies, customers, and executives mentioned in the article and what roles do they play?"),
                .init(title: "Why it matters", prompt: "Based on the article, why does this launch matter for AI infrastructure and cloud competition?"),
                .init(title: "What to watch", prompt: "Based on the article, what product or market signals should readers monitor from here?"),
                .init(title: "Next steps", prompt: "Based on the article, what comes next for manufacturing capacity and shipment timing?")
            ]
        case .legal:
            return [
                .init(title: "What happened", prompt: "Based on the article, what action did the court take and what merger decision is now delayed?"),
                .init(title: "Key players", prompt: "Who are the companies, judges, and regulators named in the article and what roles do they have?"),
                .init(title: "Why it matters", prompt: "Based on the article, why does the ruling matter for competition, consumers, and the deal timeline?"),
                .init(title: "Biggest unknowns", prompt: "What important questions remain unanswered based on the article and the antitrust review?"),
                .init(title: "What to watch", prompt: "Based on the article, what hearings, filings, or signals should readers monitor next?"),
                .init(title: "Overview", prompt: "Read more background and get the details in a general overview.")
            ]
        case .health:
            return [
                .init(title: "What happened", prompt: "Based on the article, what recommendation did the health agency expand and who is now included?"),
                .init(title: "Key players", prompt: "Who are the health officials, clinicians, or groups mentioned in the article and why do they matter?"),
                .init(title: "Why it matters", prompt: "Based on the article, why does this guidance matter for patients, clinics, and public health planning?"),
                .init(title: "Biggest unknowns", prompt: "What important questions remain unanswered based on the article and the available evidence?"),
                .init(title: "What to watch", prompt: "Based on the article, what data, uptake, or policy signals should readers monitor next?"),
                .init(title: "Learn more", prompt: "Tell me more and explore this topic with additional details from the article.")
            ]
        case .breakingNews:
            return [
                .init(title: "What happened", prompt: "Based on the article, what sequence of events caused the airport outage and service disruption overnight?"),
                .init(title: "Next steps", prompt: "Based on the article, what immediate recovery steps are expected for passengers and operations today?"),
                .init(title: "Why it matters", prompt: "Based on the article, why does this outage matter for travelers, airlines, and airport systems?"),
                .init(title: "Biggest unknowns", prompt: "What important questions remain unanswered based on the article and official statements so far?"),
                .init(title: "What to watch", prompt: "Based on the article, what updates or operational signals should readers monitor next?")
            ]
        case .narrowUpdate:
            return [
                .init(title: "What happened", prompt: "Based on the article, what decision did the city council delay and what reason was given?"),
                .init(title: "Next steps", prompt: "Based on the article, what happens next before the zoning change can return for a vote?"),
                .init(title: "Why it matters", prompt: "Based on the article, why does this delay matter for residents, builders, and the neighborhood?")
            ]
        }
    }
}
