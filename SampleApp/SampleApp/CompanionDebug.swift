import Foundation

/// When enabled, logs companion data source (SwiftData vs API), API calls, and response summary.
/// Toggle via "Debug logging" in the app or UserDefaults key "NewsCompanionDebugEnabled".
enum CompanionDebug {
    private static let key = "NewsCompanionDebugEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        print("[NewsCompanion] \(message)")
    }

    /// Call when returning cached result (no API hit).
    static func logCacheHit(url: URL) {
        log("CACHE HIT – data from SwiftData, no API call – url: \(url.absoluteString)")
    }

    /// Call when cache miss and about to call the API.
    static func logCacheMiss(url: URL) {
        log("CACHE MISS – calling Gemini API – url: \(url.absoluteString)")
    }

    /// Call after API success and save to cache.
    static func logAPISuccess(url: URL, oneLinerPrefix: String) {
        log("API SUCCESS – response received and saved to SwiftData – url: \(url.absoluteString) – oneLiner: \(oneLinerPrefix)...")
    }

    /// Call when API fails.
    static func logAPIFailure(url: URL, error: Error) {
        log("API FAILED – url: \(url.absoluteString) – error: \(error.localizedDescription)")
    }
}
