import Foundation

// MARK: - Config model (decoded from topics.json or future API)

public struct TopicValidatorConfig: Codable, Sendable {
    let fillerPhrases: [String]
    let fillerTitles: [String]
    let angles: [AngleEntry]
    let anglePriority: [String]?
    let validation: ValidationRules

    struct AngleEntry: Codable, Sendable {
        let name: String
        let keywords: [String]
    }

    struct ValidationRules: Codable, Sendable {
        let minTitleWords: Int
        let maxTitleWords: Int
        let maxTitleChars: Int
        let minPromptWords: Int
        let minScore: Int
        let maxTopics: Int
        let minPromptWordsForClarity: Int
        let groundingKeywords: [String]
        let fillerTitleWords: [String]
    }
}

// MARK: - Topic Validator

/// Deterministic post-parse validation, semantic dedup, scoring, and ordering for topic chips.
/// All rules are driven by `TopicValidatorConfig` (bundled JSON or future API payload).
enum TopicValidator {

    /// Must match angle names in topics.json (e.g. "details", "recap", "players").
    enum TopicAngle: String, CaseIterable, Sendable {
        case recap, next, players, details, impact, uncertainty, timeline, debate, watchlist, other
    }

    struct ValidatedTopic {
        let chip: TopicChip
        let angle: TopicAngle
        let score: Int
    }

    // MARK: - Bundled config (lazy-loaded once)

    private static let bundledConfig: TopicValidatorConfig = {
        guard let url = Bundle.module.url(forResource: "topics", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(TopicValidatorConfig.self, from: data) else {
            fatalError("topics.json missing or invalid in NewsCompanionKit bundle")
        }
        return config
    }()

    /// Load config from raw JSON data (for API-served configs).
    static func config(from jsonData: Data) throws -> TopicValidatorConfig {
        try JSONDecoder().decode(TopicValidatorConfig.self, from: jsonData)
    }

    /// Bundled config (from topics.json in the module bundle). Use when no custom config is provided.
    static func loadBundledConfig() -> TopicValidatorConfig {
        bundledConfig
    }

    // MARK: - Public pipeline

    /// Full pipeline: validate → dedupe → score → order → return topics (no fallback fill).
    /// When the AI returns fewer than 5 valid topics, we return only those; we do not fill with fallback templates.
    /// Pass a custom `config` to override the bundled JSON (e.g. from an API).
    static func process(
        raw: [TopicChip],
        articleTitle: String,
        config: TopicValidatorConfig? = nil
    ) -> [TopicChip] {
        let cfg = config ?? bundledConfig
        let fillerPhrasesSet = Set(cfg.fillerPhrases)
        let fillerTitlesSet = Set(cfg.fillerTitles)

        var validated = raw.compactMap { chip in
            validate(chip, cfg: cfg, fillerPhrases: fillerPhrasesSet, fillerTitles: fillerTitlesSet)
        }
        validated = deduplicateByAngle(validated)
        validated.sort { $0.score > $1.score }

        var final = Array(validated.prefix(cfg.validation.maxTopics))
        final = orderByPriority(final, cfg: cfg)

        return final.map(\.chip)
    }

    // MARK: - Single topic validation

    private static func validate(
        _ chip: TopicChip,
        cfg: TopicValidatorConfig,
        fillerPhrases: Set<String>,
        fillerTitles: Set<String>
    ) -> ValidatedTopic? {
        let title = chip.title
        let prompt = chip.prompt
        let rules = cfg.validation
        let titleWords = title.split(separator: " ")
        let promptWords = prompt.split(separator: " ")

        guard !title.isEmpty, !prompt.isEmpty else { return nil }
        guard titleWords.count >= rules.minTitleWords,
              titleWords.count <= rules.maxTitleWords else { return nil }
        guard title.count <= rules.maxTitleChars else { return nil }
        guard promptWords.count >= rules.minPromptWords else { return nil }

        let lowerTitle = title.lowercased()
        let lowerPrompt = prompt.lowercased()

        if fillerTitles.contains(lowerTitle) { return nil }
        for filler in fillerPhrases where lowerPrompt.contains(filler) { return nil }

        let angle = classifyAngle(title: lowerTitle, prompt: lowerPrompt, cfg: cfg)
        let score = computeScore(title: title, prompt: prompt, angle: angle, cfg: cfg)

        guard score >= rules.minScore else { return nil }

        return ValidatedTopic(chip: chip, angle: angle, score: score)
    }

    // MARK: - Angle classification

    private static func classifyAngle(
        title: String,
        prompt: String,
        cfg: TopicValidatorConfig
    ) -> TopicAngle {
        let combined = "\(title) \(prompt)"
        for entry in cfg.angles {
            guard let angle = TopicAngle(rawValue: entry.name) else { continue }
            for keyword in entry.keywords where combined.contains(keyword) {
                return angle
            }
        }
        return .other
    }

    // MARK: - Semantic dedup by canonical angle

    private static func deduplicateByAngle(_ topics: [ValidatedTopic]) -> [ValidatedTopic] {
        var seen = Set<String>()
        var result: [ValidatedTopic] = []
        for topic in topics.sorted(by: { $0.score > $1.score }) {
            if topic.angle == .other {
                result.append(topic)
                continue
            }
            let key = topic.angle.rawValue
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(topic)
        }
        return result
    }

    // MARK: - Priority ordering

    private static func orderByPriority(
        _ topics: [ValidatedTopic],
        cfg: TopicValidatorConfig
    ) -> [ValidatedTopic] {
        guard let priority = cfg.anglePriority, !priority.isEmpty else { return topics }
        let lookup = Dictionary(uniqueKeysWithValues: priority.enumerated().map { ($1, $0) })
        let fallback = priority.count
        return topics.sorted { a, b in
            let pa = lookup[a.angle.rawValue] ?? fallback
            let pb = lookup[b.angle.rawValue] ?? fallback
            if pa != pb { return pa < pb }
            return a.score > b.score
        }
    }

    // MARK: - Deterministic scoring

    private static func computeScore(
        title: String,
        prompt: String,
        angle: TopicAngle,
        cfg: TopicValidatorConfig
    ) -> Int {
        let rules = cfg.validation
        var score = 0

        score += (angle != .other) ? 3 : 1

        if prompt.hasSuffix("?") { score += 1 }
        if prompt.split(separator: " ").count >= rules.minPromptWordsForClarity { score += 1 }

        let lp = prompt.lowercased()
        if rules.groundingKeywords.contains(where: { lp.contains($0) }) { score += 2 }

        let lt = title.lowercased()
        if !rules.fillerTitleWords.contains(where: { lt.contains($0) }) { score += 1 }

        let wordCount = title.split(separator: " ").count
        score += (wordCount <= rules.maxTitleWords - 1) ? 2 : 1

        return score
    }

}
