import Foundation
import SwiftSoup

/// Fetches a URL and extracts article body text from HTML (no WebView).
public enum ArticleExtractor {

    public struct Result: Sendable {
        public let title: String?
        /// Extractive summary: first 3–5 sentences of the article body (for quick scan whenever a URL is used).
        public let summary: String?
        public let text: String
        public init(title: String?, summary: String?, text: String) {
            self.title = title
            self.summary = summary
            self.text = text
        }
    }

    public enum Error: Swift.Error {
        case invalidURL
        case networkFailure(Swift.Error)
        case invalidHTML
    }

    /// Fetches the URL and returns extracted title, summary, and body text.
    public static func extract(from url: URL) async throws -> Result {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw Error.invalidHTML
        }
        return try parse(html: html)
    }

    /// Parses HTML string and returns title and main article text.
    public static func parse(html: String) throws -> Result {
        let doc = try SwiftSoup.parse(html)

        let title = try? doc.select("title").first()?.text()
            ?? doc.select("meta[property=og:title]").first()?.attr("content")

        // Prefer article/main content, fallback to body text
        let bodyText: String
        if let article = try doc.select("article").first() {
            bodyText = try article.text()
        } else if let main = try doc.select("main").first() {
            bodyText = try main.text()
        } else if let content = try doc.select("[role=main], .content, .post-content, .article-body, .entry-content").first() {
            bodyText = try content.text()
        } else if let body = doc.body() {
            bodyText = try body.text()
        } else {
            bodyText = ""
        }

        let normalized = bodyText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let summary = Self.makeExtractiveSummary(from: normalized)

        return Result(
            title: title?.trimmingCharacters(in: .whitespaces).isEmpty == false ? title : nil,
            summary: summary,
            text: normalized
        )
    }

    /// Produces a 3–5 sentence extractive summary from body text (aligned with news-article-reader skill).
    private static func makeExtractiveSummary(from body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let maxSummaryLength = 600
        let paragraphs = trimmed.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        var summaryParts: [String] = []
        var totalLength = 0

        for para in paragraphs {
            guard summaryParts.count < 5, totalLength < maxSummaryLength else { break }
            let take: String
            if para.count + totalLength <= maxSummaryLength {
                take = para
            } else {
                let remaining = maxSummaryLength - totalLength
                let truncated = String(para.prefix(remaining))
                if let lastSentence = truncated.lastIndex(of: ".").map({ truncated[...$0] }) {
                    take = String(lastSentence).trimmingCharacters(in: .whitespaces)
                } else if let lastSpace = truncated.lastIndex(of: " ") {
                    take = String(truncated[..<lastSpace]).trimmingCharacters(in: .whitespaces)
                } else {
                    take = truncated.trimmingCharacters(in: .whitespaces)
                }
            }
            if !take.isEmpty {
                summaryParts.append(take)
                totalLength += take.count
            }
        }

        let summary = summaryParts.joined(separator: " ")
        return summary.isEmpty ? nil : summary
    }
}
