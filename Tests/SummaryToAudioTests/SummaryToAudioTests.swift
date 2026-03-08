import XCTest
@testable import SummaryToAudio

final class SummaryToAudioTests: XCTestCase {
    func testLanguageCodes() {
        XCTAssertEqual(SpeechLanguage.english.rawValue, "en-IN")
        XCTAssertEqual(SpeechLanguage.hindi.rawValue, "hi-IN")
        XCTAssertEqual(SpeechLanguage.tamil.rawValue, "ta-IN")
        XCTAssertEqual(SpeechLanguage.telugu.rawValue, "te-IN")
        XCTAssertEqual(SpeechLanguage.malayalam.rawValue, "ml-IN")
    }

    func testConfigInitialization() {
        let config = SpeechConfig(apiKey: "test-key", language: .hindi, rate: 1.2)
        XCTAssertEqual(config.apiKey, "test-key")
        XCTAssertEqual(config.language, .hindi)
        XCTAssertEqual(config.rate, 1.2)
    }
    
    @MainActor
    func testAudioPlayerManagerStates() {
        let manager = AudioPlayerManager()
        XCTAssertFalse(manager.isPlaying)
        XCTAssertFalse(manager.isLoading)
        
        manager.setLoading(true)
        XCTAssertTrue(manager.isLoading)
        
        manager.setError("Test Error")
        XCTAssertEqual(manager.error, "Test Error")
    }
}
