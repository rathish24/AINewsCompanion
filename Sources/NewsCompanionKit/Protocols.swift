import Foundation

// MARK: - ArticleFetching

public protocol ArticleFetching: Sendable {
    func fetch(url: URL) async throws -> ArticleContent
}

// MARK: - AICompleting

public protocol AICompleting: Sendable {
    func complete(prompt: String) async throws -> String
}
