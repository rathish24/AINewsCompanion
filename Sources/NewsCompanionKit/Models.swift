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

public struct Summary: Sendable, Codable {
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

public struct TopicChip: Sendable, Codable {
    public let title: String
    public let prompt: String
    /// Optional summary shown when the chip is selected (2-3 sentences).
    public let summary: String?

    public init(title: String, prompt: String, summary: String? = nil) {
        self.title = title
        self.prompt = prompt
        if let trimmed = summary?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty {
            self.summary = trimmed
        } else {
            self.summary = nil
        }
    }
}

// MARK: - FactCheck

public struct FactCheck: Sendable, Codable {
    public let claim: String
    public let whatToVerify: String

    public init(claim: String, whatToVerify: String) {
        self.claim = claim
        self.whatToVerify = whatToVerify
    }
}

// MARK: - CompanionResult

public struct CompanionResult: Sendable, Codable {
    public let summary: Summary
    public let topics: [TopicChip]
    public let factChecks: [FactCheck]

    public init(summary: Summary, topics: [TopicChip], factChecks: [FactCheck]) {
        self.summary = summary
        self.topics = topics
        self.factChecks = factChecks
    }
}
