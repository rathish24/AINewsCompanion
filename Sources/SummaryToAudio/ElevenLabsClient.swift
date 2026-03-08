import Foundation

// MARK: - ElevenLabs client (decoupled)
// This client is standalone: it does not depend on Sarvam or any translation service.
// Translation for non-English is done externally: source text → translation API (or custom translator) → translated text is passed to generateSpeech(text:languageCode:).
// Removing or changing the Sarvam client requires no changes in this file.

actor ElevenLabsClient {
    // See https://elevenlabs.io/docs/api-reference/text-to-speech/convert and GET /v1/voices for valid IDs.
    // Legacy premade IDs (e.g. "Rachel") can return 404; use a voice from your account or the docs example.
    private let baseURL = URL(string: "https://api.elevenlabs.io/v1")!
    private var apiKey: String?
    private var voiceId: String = "21m00Tcm4TlvDq8ikWAM" // Premade voice; override via configure(voiceId:)

    func configure(apiKey: String, voiceId: String? = nil) {
        self.apiKey = apiKey
        if let voiceId = voiceId, !voiceId.isEmpty {
            self.voiceId = voiceId
        }
    }

    /// Fetches available voices. Use this to let the user pick a voice or to fallback if default returns 404.
    func fetchVoices(includeLegacy: Bool = false) async throws -> [ElevenLabsVoice] {
        guard let apiKey = apiKey else {
            throw NSError(domain: "ElevenLabsClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key not configured"])
        }
        var url = baseURL.appendingPathComponent("voices")
        if includeLegacy {
            var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comp.queryItems = [URLQueryItem(name: "show_legacy", value: "true")]
            url = comp.url ?? url
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let list = try JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data)
        return list.voices
    }

    /// Generates speech using multilingual model. Pass languageCode for non-English (e.g. "en", "ar", "fr", "de", "it", "ru").
    func generateSpeech(text: String, languageCode: String = "en") async throws -> Data {
        guard let apiKey = apiKey else {
            print("ElevenLabsClient ERROR: API Key not configured")
            throw NSError(domain: "ElevenLabsClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key not configured"])
        }

        var url = baseURL.appendingPathComponent("text-to-speech").appendingPathComponent(voiceId)
        var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comp.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        url = comp.url ?? url
        print("ElevenLabsClient: Posting to \(url.absoluteString) language=\(languageCode)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Match verified API: body has only text + model_id; output_format in query (mp3_44100_128).
        var body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2"
        ]
        if languageCode != "en" {
            body["language_code"] = languageCode
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("ElevenLabsClient ERROR: Invalid response")
            throw NSError(domain: "ElevenLabsClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("ElevenLabsClient API ERROR (\(httpResponse.statusCode)): \(errorMsg)")
            throw NSError(domain: "ElevenLabsClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMsg)"])
        }

        print("ElevenLabsClient: Successfully received \(data.count) bytes")
        return data
    }
}

// MARK: - Voices API response (GET https://api.elevenlabs.io/v1/voices)
public struct ElevenLabsVoice: Codable, Sendable {
    public let voiceId: String
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name
    }
}

private struct ElevenLabsVoicesResponse: Codable {
    let voices: [ElevenLabsVoice]
}
