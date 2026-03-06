import Foundation

// MARK: - ArticleContent

public struct ArticleContent: Sendable {
    public let title: String
    public let text: String
    public let leadImageURL: URL?

    public init(title: String, text: String, leadImageURL: URL? = nil) {
        self.title = title
        self.text = text
        self.leadImageURL = leadImageURL
    }
}

// MARK: - Summary

public struct Summary: Sendable {
    public let oneLiner: String
    public let bullets: [String]
    public let whyItMatters: String

    public init(oneLiner: String, bullets: [String], whyItMatters: String) {
        self.oneLiner = oneLiner
        self.bullets = bullets
        self.whyItMatters = whyItMatters
    }
}

// MARK: - TopicChip

public struct TopicChip: Sendable {
    public let title: String
    public let prompt: String

    public init(title: String, prompt: String) {
        self.title = title
        self.prompt = prompt
    }
}

// MARK: - FactCheck

public struct FactCheck: Sendable {
    public let claim: String
    public let whatToVerify: String

    public init(claim: String, whatToVerify: String) {
        self.claim = claim
        self.whatToVerify = whatToVerify
    }
}

// MARK: - CompanionResult

public struct CompanionResult: Sendable {
    public let summary: Summary
    public let topics: [TopicChip]
    public let factChecks: [FactCheck]

    public init(summary: Summary, topics: [TopicChip], factChecks: [FactCheck]) {
        self.summary = summary
        self.topics = topics
        self.factChecks = factChecks
    }
}
