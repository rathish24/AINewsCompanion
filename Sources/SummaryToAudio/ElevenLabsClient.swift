import Foundation

actor ElevenLabsClient {
    private let baseURL = URL(string: "https://api.elevenlabs.io/v1/text-to-speech")!
    private var apiKey: String?
    private var voiceId: String = "21m00Tcm4lJCxeVTZ36l" // Rachel

    func configure(apiKey: String, voiceId: String? = nil) {
        self.apiKey = apiKey
        if let voiceId = voiceId {
            self.voiceId = voiceId
        }
    }

    func generateSpeech(text: String) async throws -> Data {
        guard let apiKey = apiKey else {
            print("ElevenLabsClient ERROR: API Key not configured")
            throw NSError(domain: "ElevenLabsClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key not configured"])
        }

        let url = baseURL.appendingPathComponent(voiceId)
        print("ElevenLabsClient: Posting to \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_monolingual_v1",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.5
            ]
        ]

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
