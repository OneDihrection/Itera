//
//  ButtonClickPlayer.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

/// Plays the shared tap sound for buttons and tab switches, honouring the button-sound setting.
@MainActor
final class ButtonClickPlayer {
    private let guidance: GuidanceAudioService
    private let narration: SessionAudioService

    init(guidance: GuidanceAudioService, narration: SessionAudioService) {
        self.guidance = guidance
        self.narration = narration
    }

    func play() {
        guard UserDefaults.standard.object(forKey: PracticePreferences.buttonSounds) as? Bool ?? true else {
            return
        }

        // A tap sound never lands on top of narration from a running session.
        guard !narration.isNarrating else {
            return
        }

        guidance.playButtonClick()
    }
}
