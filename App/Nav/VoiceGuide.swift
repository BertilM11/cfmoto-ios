// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import AVFoundation

/// Instrucciones por voz. Baja el volumen de la música mientras habla y, con el modo "audio"
/// en segundo plano, sigue hablando con el iPhone bloqueado.
final class VoiceGuide: NSObject, AVSpeechSynthesizerDelegate {
    var muted = false {
        didSet {
            if muted { synthesizer.stopSpeaking(at: .immediate) }
        }
    }

    private let synthesizer = AVSpeechSynthesizer()

    private lazy var voice: AVSpeechSynthesisVoice? = {
        for language in ["es-MX", "es-US", "es-419", "es-ES"] {
            if let v = AVSpeechSynthesisVoice(language: language) { return v }
        }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("es") }
    }()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        logLine("[VOZ] \(text)")
        guard !muted else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking {
            // Devolver el volumen a la música.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
