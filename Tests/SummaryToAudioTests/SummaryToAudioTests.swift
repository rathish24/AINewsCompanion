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
        let config = SpeechConfig(provider: .sarvam, sarvamLanguage: .hindi, elevenLabsLanguage: .french, rate: 1.2)
        XCTAssertEqual(config.sarvamLanguage, .hindi)
        XCTAssertEqual(config.elevenLabsLanguage, .french)
        XCTAssertEqual(config.rate, 1.2)
        XCTAssertEqual(config.effectiveLanguage().cacheKey, "hi-IN")
        let configEL = SpeechConfig(provider: .elevenLabs, sarvamLanguage: .tamil, elevenLabsLanguage: .german, rate: 1.0)
        XCTAssertEqual(configEL.effectiveLanguage().cacheKey, "de")
    }

    func testElevenLabsLanguageCodes() {
        XCTAssertEqual(ElevenLabsLanguage.english.languageCode, "en")
        XCTAssertEqual(ElevenLabsLanguage.arabic.languageCode, "ar")
        XCTAssertEqual(ElevenLabsLanguage.french.languageCode, "fr")
        XCTAssertEqual(ElevenLabsLanguage.german.languageCode, "de")
        XCTAssertEqual(ElevenLabsLanguage.spanish.languageCode, "es")
        XCTAssertEqual(ElevenLabsLanguage.japanese.languageCode, "ja")
        XCTAssertEqual(ElevenLabsLanguage.chinese.languageCode, "zh")
        XCTAssertEqual(ElevenLabsLanguage.filipino.languageCode, "fil")
        XCTAssertEqual(ElevenLabsLanguage.allCases.count, 29)
    }

    func testEffectiveTTSLanguageIsEnglish() {
        XCTAssertTrue(EffectiveTTSLanguage.sarvam(.english).isEnglish)
        XCTAssertFalse(EffectiveTTSLanguage.sarvam(.hindi).isEnglish)
        XCTAssertTrue(EffectiveTTSLanguage.elevenLabs(.english).isEnglish)
        XCTAssertFalse(EffectiveTTSLanguage.elevenLabs(.french).isEnglish)
    }

    func testEffectiveTTSLanguageCacheKey() {
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.english).cacheKey, "en-IN")
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.tamil).cacheKey, "ta-IN")
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.hindi).cacheKey, "hi-IN")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.english).cacheKey, "en")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.french).cacheKey, "fr")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.tamil).cacheKey, "ta")
    }

    func testEffectiveTTSLanguageProvider() {
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.tamil).provider, .sarvam)
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.french).provider, .elevenLabs)
    }

    func testEffectiveTTSLanguageEnglishCacheKeyForFallback() {
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.tamil).englishCacheKeyForFallback, "en-IN")
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.hindi).englishCacheKeyForFallback, "en-IN")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.french).englishCacheKeyForFallback, "en")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.german).englishCacheKeyForFallback, "en")
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
