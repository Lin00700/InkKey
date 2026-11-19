//
//  InkSpeech.swift
//  InkKey / InkKeyKeyboard
//
//  English pronunciation through AVSpeechSynthesizer.  Works from both the app
//  and the keyboard extension (the extension needs "Allow Full Access").
//

import AVFoundation
import UIKit

final class InkSpeech {
    static let shared = InkSpeech()

    private let synthesizer = AVSpeechSynthesizer()
    private var audioConfigured = false

    private init() {}

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String, language: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configureAudioIfNeeded()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        let code = language ?? InkSettings.shared.accent.language
        utterance.voice = AVSpeechSynthesisVoice(language: code)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        let rate = min(max(InkSettings.shared.speechRate, 0.2), 0.75)
        utterance.rate = Float(rate)
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func configureAudioIfNeeded() {
        guard !audioConfigured else { return }
        audioConfigured = true
        #if INKKEY_APP
        // Only the host app configures the session; the keyboard keeps the
        // user's current audio session so it stays extension-safe.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true, options: [])
        #endif
    }
}

enum InkFeedback {
    private static let impact = UIImpactFeedbackGenerator(style: .light)

    static func tap() {
        guard InkSettings.shared.hapticsEnabled else { return }
        impact.prepare()
        impact.impactOccurred()
    }

    static func soft() {
        guard InkSettings.shared.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
