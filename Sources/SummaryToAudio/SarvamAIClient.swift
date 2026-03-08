import Foundation

public enum SarvamAIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case apiError(String)
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "The Sarvam AI API URL is invalid."
        case .networkError(let error): return "Network error connecting to Sarvam AI: \(error.localizedDescription)"
        case .apiError(let message): return "Sarvam AI API Error: \(message)"
        case .invalidData: return "Received invalid or empty audio data from Sarvam AI."
        }
    }
}


public actor SarvamAIClient {
    private var apiKey: String?
    private let baseURL = URL(string: "https://api.sarvam.ai/text-to-speech")!

    public init() {}

    public func configure(apiKey: String) {
        self.apiKey = apiKey
    }

    public func generateSpeech(text: String, language: SpeechLanguage) async throws -> Data {
        guard let key = apiKey else {
            throw SarvamAIError.apiError("Sarvam AI key not configured")
        }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "api-subscription-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "target_language_code": language.rawValue,
            "speaker": "aditya",
            "model": "bulbul:v3" // Updated to v3 for better support
        ]

        print("SarvamAIClient: Generating speech for text (\(text.count) chars): [\(text)]")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("SarvamAIClient Network ERROR: \(error.localizedDescription)")
            throw SarvamAIError.networkError(error)
        }
        
        print("SarvamAIClient: Received response from \(baseURL)")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("SarvamAIClient ERROR: Invalid response type")
            throw SarvamAIError.invalidData
        }

        print("SarvamAIClient Status Code: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("SarvamAIClient API ERROR: \(errorMsg)")
            throw SarvamAIError.apiError(errorMsg)
        }

        // Sarvam AI returns JSON with base64 encoded audio segments in "audios" array
        struct Response: Codable {
            let audios: [String]
        }

        let decodedResponse = try JSONDecoder().decode(Response.self, from: data)
        guard !decodedResponse.audios.isEmpty else {
            print("SarvamAIClient ERROR: No audio segments returned")
            throw SarvamAIError.invalidData
        }

        print("SarvamAIClient: Received \(decodedResponse.audios.count) audio segments")
        
        var combinedData = Data()
        for (index, base64Audio) in decodedResponse.audios.enumerated() {
            guard let segmentData = Data(base64Encoded: base64Audio) else {
                print("SarvamAIClient ERROR: Failed to decode segment \(index)")
                continue
            }
            combinedData.append(segmentData)
        }

        guard !combinedData.isEmpty else {
            print("SarvamAIClient ERROR: Combined audio data is empty")
            throw SarvamAIError.invalidData
        }

        print("SarvamAIClient: Total combined audio data size: \(combinedData.count) bytes")
        return combinedData
    }

    public func translate(text: String, targetLanguage: SpeechLanguage) async throws -> String {
        guard let key = apiKey else {
            throw SarvamAIError.apiError("Sarvam AI key not configured")
        }
        let url = URL(string: "https://api.sarvam.ai/translate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "api-subscription-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "input": text,
            "source_language_code": "en-IN",
            "target_language_code": targetLanguage.rawValue,
            "model": "mayura:v1"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SarvamAIError.invalidData
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SarvamAIError.apiError(errorMsg)
        }

        struct TranslateResponse: Codable {
            let translated_text: String
        }

        let decodedResponse = try JSONDecoder().decode(TranslateResponse.self, from: data)
        return decodedResponse.translated_text
    }
}
