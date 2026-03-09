import Foundation

/// Loaded translation prompt from translation.json.
public struct TranslationPromptModel: Codable, Sendable {
    public let instruction: String
    public let outputKey: String

    public init(instruction: String, outputKey: String) {
        self.instruction = instruction
        self.outputKey = outputKey
    }

    enum CodingKeys: String, CodingKey {
        case instruction
        case outputKey = "output_key"
    }
}
