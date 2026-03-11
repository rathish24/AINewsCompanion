import Foundation
import AVFoundation

// MARK: - System TTS Client (AVSpeechSynthesizer — no API key required)
// Uses iOS/macOS built-in voices. Audio is rendered directly through AVSpeechSynthesizer,
// bypassing AudioPlayerManager (which expects Data). We drive isPlaying state manually via the delegate.

@MainActor
final class SystemTTSClient: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var onFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, language: SystemTTSLanguage) {
        stop()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.languageCode)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        print("SystemTTSClient: Speaking \(text.count) chars in \(language.languageCode)")
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }
    var isPaused: Bool   { synthesizer.isPaused }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinished?() }
    }
}
