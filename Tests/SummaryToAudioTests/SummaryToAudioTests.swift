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
        let configAWS = SpeechConfig(provider: .awsSpeech, sarvamLanguage: .english, elevenLabsLanguage: .english, awsPollyLanguage: .french)
        XCTAssertEqual(configAWS.effectiveLanguage().cacheKey, "fr-FR")
        guard case .awsPolly(let lang) = configAWS.effectiveLanguage() else {
            XCTFail("Expected .awsPolly(lang) for awsSpeech provider")
            return
        }
        XCTAssertEqual(lang, .french)
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

    func testElevenLabsLanguageAWSTranslateTargetCode() {
        XCTAssertEqual(ElevenLabsLanguage.english.awsTranslateTargetCode, "en")
        XCTAssertEqual(ElevenLabsLanguage.french.awsTranslateTargetCode, "fr")
        XCTAssertEqual(ElevenLabsLanguage.filipino.awsTranslateTargetCode, "tl")
        XCTAssertEqual(ElevenLabsLanguage.tamil.awsTranslateTargetCode, "ta")
    }

    func testEffectiveTTSLanguageIsEnglish() {
        XCTAssertTrue(EffectiveTTSLanguage.sarvam(.english).isEnglish)
        XCTAssertFalse(EffectiveTTSLanguage.sarvam(.hindi).isEnglish)
        XCTAssertTrue(EffectiveTTSLanguage.elevenLabs(.english).isEnglish)
        XCTAssertFalse(EffectiveTTSLanguage.elevenLabs(.french).isEnglish)
        XCTAssertTrue(EffectiveTTSLanguage.awsPolly(.english).isEnglish)
        XCTAssertFalse(EffectiveTTSLanguage.awsPolly(.french).isEnglish)
    }

    func testEffectiveTTSLanguageCacheKey() {
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.english).cacheKey, "en-IN")
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.tamil).cacheKey, "ta-IN")
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.hindi).cacheKey, "hi-IN")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.english).cacheKey, "en")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.french).cacheKey, "fr")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.tamil).cacheKey, "ta")
        XCTAssertEqual(EffectiveTTSLanguage.awsPolly(.english).cacheKey, "en-US")
        XCTAssertEqual(EffectiveTTSLanguage.awsPolly(.french).cacheKey, "fr-FR")
        XCTAssertEqual(EffectiveTTSLanguage.awsPolly(.hindi).cacheKey, "hi-IN")
    }

    func testEffectiveTTSLanguageProvider() {
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.tamil).provider, .sarvam)
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.french).provider, .elevenLabs)
        XCTAssertEqual(EffectiveTTSLanguage.awsPolly(.french).provider, .awsSpeech)
    }

    func testEffectiveTTSLanguageEnglishCacheKeyForFallback() {
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.tamil).englishCacheKeyForFallback, "en-IN")
        XCTAssertEqual(EffectiveTTSLanguage.sarvam(.hindi).englishCacheKeyForFallback, "en-IN")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.french).englishCacheKeyForFallback, "en")
        XCTAssertEqual(EffectiveTTSLanguage.elevenLabs(.german).englishCacheKeyForFallback, "en")
        XCTAssertEqual(EffectiveTTSLanguage.awsPolly(.french).englishCacheKeyForFallback, "en-US")
        XCTAssertEqual(EffectiveTTSLanguage.awsPolly(.hindi).englishCacheKeyForFallback, "en-US")
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

    // MARK: - Provider + language → correct TTS language (bug: switched to Sarvam + Tamil still played English)

    /// After "switching" to Sarvam and selecting Tamil, effective language must be Sarvam Tamil so playback uses Tamil.
    func testSarvamProviderWithTamilUsesTamilLanguage() {
        let config = SpeechConfig(provider: .sarvam, sarvamLanguage: .tamil, elevenLabsLanguage: .english)
        let effective = config.effectiveLanguage()
        guard case .sarvam(let lang) = effective else {
            XCTFail("Expected .sarvam(lang), got \(effective)")
            return
        }
        XCTAssertEqual(lang, .tamil, "Sarvam with selected Tamil must use Tamil for TTS")
        XCTAssertEqual(effective.cacheKey, "ta-IN")
    }

    /// After "switching" to Sarvam and selecting Hindi, effective language must be Sarvam Hindi.
    func testSarvamProviderWithHindiUsesHindiLanguage() {
        let config = SpeechConfig(provider: .sarvam, sarvamLanguage: .hindi, elevenLabsLanguage: .english)
        let effective = config.effectiveLanguage()
        guard case .sarvam(let lang) = effective else {
            XCTFail("Expected .sarvam(lang), got \(effective)")
            return
        }
        XCTAssertEqual(lang, .hindi)
        XCTAssertEqual(effective.cacheKey, "hi-IN")
    }

    /// After "switching" to ElevenLabs and selecting French, effective language must be ElevenLabs French.
    func testElevenLabsProviderWithFrenchUsesFrenchLanguage() {
        let config = SpeechConfig(provider: .elevenLabs, sarvamLanguage: .english, elevenLabsLanguage: .french)
        let effective = config.effectiveLanguage()
        guard case .elevenLabs(let lang) = effective else {
            XCTFail("Expected .elevenLabs(lang), got \(effective)")
            return
        }
        XCTAssertEqual(lang, .french)
        XCTAssertEqual(effective.cacheKey, "fr")
    }

    /// Simulates UI: user was on ElevenLabs, switched to Sarvam, then selected Tamil. Effective TTS language must be Sarvam Tamil.
    func testSwitchToSarvamAndSelectTamil_PlayUsesTamil() {
        let effectiveFromUI = EffectiveTTSLanguage.sarvam(.tamil)
        XCTAssertEqual(effectiveFromUI.provider, .sarvam)
        XCTAssertEqual(effectiveFromUI.cacheKey, "ta-IN")
        if case .sarvam(let lang) = effectiveFromUI {
            XCTAssertEqual(lang, .tamil)
        } else {
            XCTFail("Effective language must be .sarvam(.tamil) when Sarvam tab and Tamil selected")
        }
    }

    /// Simulates UI: user was on Sarvam, switched to ElevenLabs, then selected Japanese. Effective TTS language must be ElevenLabs Japanese.
    func testSwitchToElevenLabsAndSelectJapanese_PlayUsesJapanese() {
        let effectiveFromUI = EffectiveTTSLanguage.elevenLabs(.japanese)
        XCTAssertEqual(effectiveFromUI.provider, .elevenLabs)
        XCTAssertEqual(effectiveFromUI.cacheKey, "ja")
        if case .elevenLabs(let lang) = effectiveFromUI {
            XCTAssertEqual(lang, .japanese)
        } else {
            XCTFail("Effective language must be .elevenLabs(.japanese) when ElevenLabs tab and Japanese selected")
        }
    }

    /// For any Sarvam language selection, config.effectiveLanguage() returns that language (play will use it).
    func testSarvamProvider_EveryLanguageSelection_EffectiveLanguageMatches() {
        for sarvamLang in SpeechLanguage.allCases {
            let config = SpeechConfig(provider: .sarvam, sarvamLanguage: sarvamLang, elevenLabsLanguage: .english)
            let effective = config.effectiveLanguage()
            guard case .sarvam(let lang) = effective else {
                XCTFail("Sarvam config must yield .sarvam(lang), got \(effective) for \(sarvamLang)")
                return
            }
            XCTAssertEqual(lang, sarvamLang, "Sarvam with \(sarvamLang) must use \(sarvamLang) for TTS")
            XCTAssertEqual(effective.cacheKey, sarvamLang.languageCode)
        }
    }

    /// For any ElevenLabs language selection, config.effectiveLanguage() returns that language (play will use it).
    func testElevenLabsProvider_EveryLanguageSelection_EffectiveLanguageMatches() {
        for elevenLang in ElevenLabsLanguage.allCases {
            let config = SpeechConfig(provider: .elevenLabs, sarvamLanguage: .english, elevenLabsLanguage: elevenLang)
            let effective = config.effectiveLanguage()
            guard case .elevenLabs(let lang) = effective else {
                XCTFail("ElevenLabs config must yield .elevenLabs(lang), got \(effective) for \(elevenLang)")
                return
            }
            XCTAssertEqual(lang, elevenLang, "ElevenLabs with \(elevenLang) must use \(elevenLang) for TTS")
            XCTAssertEqual(effective.cacheKey, elevenLang.languageCode)
        }
    }

    // MARK: - Client (provider) change: play must use new client's language (bug: Sarvam audio kept playing after switch to ElevenLabs)

    /// After switching client from Sarvam to ElevenLabs, next play must use ElevenLabs (e.g. English), not Sarvam Tamil.
    func testClientChangeFromSarvamToElevenLabs_PlayUsesElevenLabsLanguage() {
        var config = SpeechConfig(provider: .sarvam, sarvamLanguage: .tamil, elevenLabsLanguage: .english)
        XCTAssertEqual(config.effectiveLanguage().provider, .sarvam)
        if case .sarvam(let lang) = config.effectiveLanguage() { XCTAssertEqual(lang, .tamil) }

        config.provider = .elevenLabs
        let effective = config.effectiveLanguage()
        XCTAssertEqual(effective.provider, .elevenLabs, "After switching to ElevenLabs, play must use ElevenLabs client")
        guard case .elevenLabs(let lang) = effective else {
            XCTFail("Effective language must be .elevenLabs(lang) after provider switch")
            return
        }
        XCTAssertEqual(lang, .english)
        XCTAssertEqual(effective.cacheKey, "en")
    }

    /// After switching client from ElevenLabs to Sarvam, next play must use Sarvam (e.g. Tamil), not ElevenLabs.
    func testClientChangeFromElevenLabsToSarvam_PlayUsesSarvamLanguage() {
        var config = SpeechConfig(provider: .elevenLabs, sarvamLanguage: .tamil, elevenLabsLanguage: .french)
        XCTAssertEqual(config.effectiveLanguage().provider, .elevenLabs)

        config.provider = .sarvam
        let effective = config.effectiveLanguage()
        XCTAssertEqual(effective.provider, .sarvam, "After switching to Sarvam, play must use Sarvam client")
        guard case .sarvam(let lang) = effective else {
            XCTFail("Effective language must be .sarvam(lang) after provider switch")
            return
        }
        XCTAssertEqual(lang, .tamil)
        XCTAssertEqual(effective.cacheKey, "ta-IN")
    }

    /// When client is changed, effective language must be the new client's selected language (ensures replay cache clear + stop are used so play uses new audio).
    func testClientChange_EffectiveLanguageIsNewClientLanguage() {
        // Sarvam Tamil → switch to ElevenLabs German
        let configAfterSwitch = SpeechConfig(provider: .elevenLabs, sarvamLanguage: .tamil, elevenLabsLanguage: .german)
        let effective = configAfterSwitch.effectiveLanguage()
        XCTAssertEqual(effective.provider, .elevenLabs)
        if case .elevenLabs(let lang) = effective {
            XCTAssertEqual(lang, .german)
            XCTAssertEqual(effective.cacheKey, "de")
        } else {
            XCTFail("Expected .elevenLabs(.german)")
        }
    }

    // MARK: - AWS Polly (AWSpeech tab)

    func testAWSPollyLanguageCodesAndTranslateTargets() {
        XCTAssertEqual(AWSPollyLanguage.english.languageCode, "en-US")
        XCTAssertEqual(AWSPollyLanguage.english.translateTargetCode, "en")
        XCTAssertEqual(AWSPollyLanguage.french.languageCode, "fr-FR")
        XCTAssertEqual(AWSPollyLanguage.french.translateTargetCode, "fr")
        XCTAssertEqual(AWSPollyLanguage.hindi.languageCode, "hi-IN")
        XCTAssertEqual(AWSPollyLanguage.hindi.translateTargetCode, "hi")
        XCTAssertEqual(AWSPollyLanguage.japanese.languageCode, "ja-JP")
        XCTAssertEqual(AWSPollyLanguage.japanese.translateTargetCode, "ja")
    }

    func testAWSPollyLanguage_EveryCaseHasTranslateTarget() {
        for lang in AWSPollyLanguage.allCases {
            let code = lang.translateTargetCode
            XCTAssertFalse(code.isEmpty, "\(lang) must have non-empty translateTargetCode")
            XCTAssertEqual(code.count, 2, "\(lang) translateTargetCode should be ISO 639-1 (e.g. en, fr)")
        }
    }

    func testAWSPollyProvider_EveryLanguageSelection_EffectiveLanguageMatches() {
        for pollyLang in AWSPollyLanguage.allCases {
            let config = SpeechConfig(provider: .awsSpeech, sarvamLanguage: .english, elevenLabsLanguage: .english, awsPollyLanguage: pollyLang)
            let effective = config.effectiveLanguage()
            guard case .awsPolly(let lang) = effective else {
                XCTFail("awsSpeech config must yield .awsPolly(lang), got \(effective) for \(pollyLang)")
                return
            }
            XCTAssertEqual(lang, pollyLang)
            XCTAssertEqual(effective.cacheKey, pollyLang.languageCode)
            XCTAssertEqual(effective.provider, .awsSpeech)
        }
    }

    func testAWSPollyLanguage_AllCasesPollySupported() {
        for lang in AWSPollyLanguage.allCases {
            XCTAssertTrue(lang.isPollySupported, "\(lang.rawValue) must be in Polly supported set for 100% confidence")
        }
    }
}
