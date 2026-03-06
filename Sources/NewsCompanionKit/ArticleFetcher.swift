import Foundation
import SwiftSoup

/// Extracts clean article content from a URL. Uses HTML extraction with optional memory + disk cache.
public final class ArticleFetcher: ArticleFetching, @unchecked Sendable {

    public struct Configuration: Sendable {
        public var maxCacheAge: TimeInterval
        public var maxArticleLength: Int
        public init(maxCacheAge: TimeInterval = 3600, maxArticleLength: Int = 50_000) {
            self.maxCacheAge = maxCacheAge
            self.maxArticleLength = maxArticleLength
        }
    }

    private let config: Configuration
    private let customFetcher: (any ArticleFetching)?
    private var memoryCache: [URL: (content: ArticleContent, date: Date)] = [:]
    private let queue = NSLock()
    private let diskCacheURL: URL?

    public init(config: Configuration = .init(), customFetcher: (any ArticleFetching)? = nil, diskCacheDirectory: URL? = nil) {
        self.config = config
        self.customFetcher = customFetcher
        self.diskCacheURL = diskCacheDirectory
    }

    public func fetch(url: URL) async throws -> ArticleContent {
        if let custom = customFetcher {
            do {
                return try await custom.fetch(url: url)
            } catch {
                // Fall through to HTML extraction
            }
        }
        if let cached = getFromMemoryCache(url: url) { return cached }
        if let cached = await getFromDiskCache(url: url) { return cached }
        let content = try await extractFromHTML(url: url)
        setMemoryCache(url: url, content: content)
        await setDiskCache(url: url, content: content)
        return content
    }

    // MARK: - HTML extraction

    private func extractFromHTML(url: URL) async throws -> ArticleContent {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { throw ArticleFetcherError.invalidHTML }
        return try parseHTML(html, url: url)
    }

    private func parseHTML(_ html: String, url: URL) throws -> ArticleContent {
        let doc = try SwiftSoup.parse(html)
        let title = (try? doc.select("title").first()?.text())
            ?? (try? doc.select("meta[property=og:title]").first()?.attr("content"))
            ?? ""
        let leadImageURLString = try? doc.select("meta[property=og:image]").first()?.attr("content")
        let leadImageURL: URL? = leadImageURLString.flatMap { URL(string: $0, relativeTo: url) }

        var bodyText: String
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

        let trimmed = String(normalized.prefix(config.maxArticleLength))
        return ArticleContent(title: title.isEmpty ? "Untitled" : title, text: trimmed, leadImageURL: leadImageURL)
    }

    // MARK: - Memory cache

    private func getFromMemoryCache(url: URL) -> ArticleContent? {
        queue.lock()
        defer { queue.unlock() }
        guard let entry = memoryCache[url], Date().timeIntervalSince(entry.date) < config.maxCacheAge else {
            memoryCache[url] = nil
            return nil
        }
        return entry.content
    }

    private func setMemoryCache(url: URL, content: ArticleContent) {
        queue.lock()
        memoryCache[url] = (content, Date())
        queue.unlock()
    }

    // MARK: - Disk cache

    private func cacheFileURL(for url: URL) -> URL? {
        guard let base = diskCacheURL else { return nil }
        let key = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url.absoluteString
        return base.appendingPathComponent(key)
    }

    private func getFromDiskCache(url: URL) async -> ArticleContent? {
        guard let fileURL = cacheFileURL(for: url) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(CachedArticle.self, from: data)
            if Date().timeIntervalSince(decoded.date) > config.maxCacheAge { return nil }
            return decoded.content
        } catch {
            return nil
        }
    }

    private func setDiskCache(url: URL, content: ArticleContent) async {
        guard let fileURL = cacheFileURL(for: url) else { return }
        let cached = CachedArticle(content: content, date: Date())
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cached).write(to: fileURL)
    }
}

private struct CachedArticle: Codable {
    let content: ArticleContent
    let date: Date
}

extension ArticleContent: Codable {
    enum CodingKeys: String, CodingKey { case title, text, leadImageURL }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        leadImageURL = try c.decodeIfPresent(URL.self, forKey: .leadImageURL)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(leadImageURL, forKey: .leadImageURL)
    }
}

public enum ArticleFetcherError: Error {
    case invalidHTML
}
