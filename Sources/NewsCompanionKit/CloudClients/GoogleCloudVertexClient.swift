import Foundation

/// Google Cloud Vertex AI client for article-to-summary. Use your project, location, and model name.
/// Conforms to `AICompleting`; pass the model you have available (e.g. `gemini-1.5-flash`, `gemini-1.5-pro`).
/// API key (or Bearer token) can be empty for local validation; requests will fail at runtime until you provide credentials.
public final class GoogleCloudVertexClient: AICompleting, Sendable {

    private let project: String
    private let location: String
    private let model: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let additionalHeaders: [String: String]?

    /// - Parameters:
    ///   - project: Google Cloud project ID.
    ///   - location: Region (e.g. `us-central1`).
    ///   - model: Model name on your Vertex AI server (e.g. `gemini-1.5-flash`, `gemini-1.5-pro`).
    ///   - apiKey: Bearer token or API key for auth. Pass empty string to only validate client creation.
    ///   - timeout: Request timeout in seconds.
    ///   - additionalHeaders: Optional extra HTTP headers. Applied after default headers.
    public init(
        project: String,
        location: String,
        model: String,
        apiKey: String,
        timeout: TimeInterval = 60,
        additionalHeaders: [String: String]? = nil
    ) {
        self.project = project
        self.location = location
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.additionalHeaders = additionalHeaders
    }

    public func complete(prompt: String) async throws -> String {
        let path = "v1/projects/\(project)/locations/\(location)/publishers/google/models/\(model):generateContent"
        let urlString = "https://\(location)-aiplatform.googleapis.com/\(path)"
        guard let url = URL(string: urlString) else {
            print("[GoogleCloudVertexClient] invalid URL")
            throw AIClientError.apiError("Invalid Vertex AI URL")
        }
        print("[GoogleCloudVertexClient] request – project: \(project) location: \(location) model: \(model) promptLength: \(prompt.count)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = timeout
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 4096,
                "responseMimeType": "application/json"
            ] as [String: Any]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[GoogleCloudVertexClient] invalid response (not HTTPURLResponse)")
            throw AIClientError.invalidResponse
        }
        if http.statusCode != 200 {
            let msg = Self.parseError(data, statusCode: http.statusCode)
            print("[GoogleCloudVertexClient] HTTP \(http.statusCode) – \(msg)")
            throw AIClientError.apiError(msg)
        }
        let content = try Self.parseVertexResponse(data)
        print("[GoogleCloudVertexClient] success – responseLength: \(content.count)")
        return content
    }

    private static func parseVertexResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let part = parts.first,
              let text = part["text"] as? String else {
            throw AIClientError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseError(_ data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        return "HTTP \(statusCode)"
    }
}
