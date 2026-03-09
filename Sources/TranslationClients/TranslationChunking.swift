import Foundation

enum TranslationChunking {

    /// Splits text into chunks of at most `maxCharacters` characters, preferring to break at sentence or word boundaries.
    static func chunks(for text: String, maxCharacters: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > maxCharacters else { return [trimmed] }

        var result: [String] = []
        var remaining = trimmed
        while !remaining.isEmpty {
            if remaining.count <= maxCharacters {
                result.append(remaining)
                break
            }
            let segment = String(remaining.prefix(maxCharacters))
            let breakIndex: String.Index
            if let lastSentence = segment.lastIndex(of: ".").map({ segment.index(after: $0) }),
               lastSentence > segment.startIndex {
                breakIndex = lastSentence
            } else if let lastNewline = segment.lastIndex(of: "\n").map({ segment.index(after: $0) }),
                      lastNewline > segment.startIndex {
                breakIndex = lastNewline
            } else if let lastSpace = segment.lastIndex(of: " ") {
                breakIndex = segment.index(after: lastSpace)
            } else {
                breakIndex = segment.endIndex
            }
            let chunk = String(segment[..<breakIndex]).trimmingCharacters(in: .whitespaces)
            if !chunk.isEmpty { result.append(chunk) }
            remaining = String(remaining[breakIndex...]).trimmingCharacters(in: .whitespaces)
        }
        return result.isEmpty ? [trimmed] : result
    }

    /// Splits text into chunks of at most `maxUTF8Bytes` bytes. Keeps UTF-8 sequences intact.
    static func chunksByBytes(for text: String, maxUTF8Bytes: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let utf8 = Array(trimmed.utf8)
        guard utf8.count > maxUTF8Bytes else { return [trimmed] }

        var result: [String] = []
        var start = 0
        while start < utf8.count {
            var end = min(start + maxUTF8Bytes, utf8.count)
            while end > start && (utf8[end - 1] & 0xC0) == 0x80 { end -= 1 }
            if let chunk = String(bytes: utf8[start..<end], encoding: .utf8) {
                result.append(chunk)
            }
            start = end
        }
        return result
    }
}
