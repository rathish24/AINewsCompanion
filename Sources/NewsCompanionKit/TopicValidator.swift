import Foundation

// MARK: - Config model (decoded from topics.json or future API)

public struct TopicValidatorConfig: Codable, Sendable {
    let fillerPhrases: [String]
    let fillerTitles: [String]
    let angles: [AngleEntry]
    let fallbackTemplates: [FallbackEntry]
    let validation: ValidationRules

    struct AngleEntry: Codable, Sendable {
        let name: String
        let keywords: [String]
    }

    struct FallbackEntry: Codable, Sendable {
        let title: String
        let prompt: String
        let angle: String
    }

    struct ValidationRules: Codable, Sendable {
        let minTitleWords: Int
        let maxTitleWords: Int
        let maxTitleChars: Int
        let minPromptWords: Int
        let minScore: Int
        let minTopics: Int
        let maxTopics: Int
        let minPromptWordsForClarity: Int
        let groundingKeywords: [String]
        let fillerTitleWords: [String]
    }
}

// MARK: - Topic Validator

/// Deterministic post-parse validation, semantic dedup, scoring, and fallback for topic chips.
/// All rules are driven by `TopicValidatorConfig` (bundled JSON or future API payload).
enum TopicValidator {

    enum TopicAngle: String, CaseIterable, Sendable {
        case recap, next, players, impact, uncertainty, timeline, debate, watchlist, other
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

    /// Full pipeline: validate → dedupe → score → fallback → return best topics.
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

        if validated.count < cfg.validation.minTopics {
            let fallbacks = buildFallbacks(existing: validated, cfg: cfg)
            validated.append(contentsOf: fallbacks)
        }

        return Array(validated.prefix(cfg.validation.maxTopics)).map(\.chip)
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

    // MARK: - Fallback topics

    private static func buildFallbacks(
        existing: [ValidatedTopic],
        cfg: TopicValidatorConfig
    ) -> [ValidatedTopic] {
        let usedAngles = Set(existing.map(\.angle.rawValue))
        let needed = max(0, cfg.validation.minTopics - existing.count)
        var fallbacks: [ValidatedTopic] = []

        for template in cfg.fallbackTemplates {
            guard fallbacks.count < needed else { break }
            guard !usedAngles.contains(template.angle) else { continue }
            let angle = TopicAngle(rawValue: template.angle) ?? .other
            let chip = TopicChip(title: template.title, prompt: template.prompt)
            let score = computeScore(title: chip.title, prompt: chip.prompt, angle: angle, cfg: cfg)
            fallbacks.append(ValidatedTopic(chip: chip, angle: angle, score: score))
        }
        return fallbacks
    }
}
