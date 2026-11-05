//
//  NarrationVoice.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import AVFoundation

/// Chooses the most natural installed system voice and the shared narration pacing.
///
/// `AVSpeechSynthesisVoice(language:)` returns the default compact voice even when a
/// higher-quality one is downloaded, so narration selects explicitly by quality here.
/// Both audio services stay the sole owners of their synthesizers; this type only
/// describes which voice and pacing to use.
enum NarrationVoice {
    /// Slower than the system default, for older patients following movement cues.
    static let rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
    /// Short breaths around each utterance so consecutive cues do not run together.
    static let preUtteranceDelay: TimeInterval = 0.1
    static let postUtteranceDelay: TimeInterval = 0.25

    /// The highest-quality installed voice for a BCP-47 language such as "id-ID".
    ///
    /// Prefers an exact language match, then the same base language ("id"), and skips
    /// novelty voices and Personal Voice. Returns `nil` only when no voice exists at all.
    static func best(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter(isNarrationVoice)
        let base = language.split(separator: "-").first.map(String.init) ?? language

        let exact = candidates.filter { $0.language == language }
        let sameBase = candidates.filter { $0.language.hasPrefix(base + "-") || $0.language == base }
        let pool = exact.isEmpty ? sameBase : exact

        return pool.max(by: isLowerQuality) ?? AVSpeechSynthesisVoice(language: language)
    }

    /// What Settings shows about the voice narration will use.
    struct Summary: Equatable {
        let name: String
        /// Enhanced or premium; the standard compact voice sounds noticeably robotic.
        let isHighQuality: Bool
    }

    static func summary(for language: String) -> Summary? {
        best(for: language).map {
            Summary(name: $0.name, isHighQuality: $0.quality != .default)
        }
    }

    /// An utterance with the shared voice and pacing.
    static func utterance(_ text: String, voice: AVSpeechSynthesisVoice) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        // Altered pitch sounds artificial; keep the voice's natural pitch.
        utterance.pitchMultiplier = 1
        utterance.preUtteranceDelay = preUtteranceDelay
        utterance.postUtteranceDelay = postUtteranceDelay
        return utterance
    }

    // MARK: - Selection rules

    private static func isNarrationVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        !voice.voiceTraits.contains(.isNoveltyVoice)
            && !voice.voiceTraits.contains(.isPersonalVoice)
    }

    /// Orders by quality (premium above enhanced above default), then by name for stability.
    private static func isLowerQuality(_ lhs: AVSpeechSynthesisVoice, _ rhs: AVSpeechSynthesisVoice) -> Bool {
        if lhs.quality != rhs.quality {
            return lhs.quality.rawValue < rhs.quality.rawValue
        }

        return lhs.name > rhs.name
    }
}
