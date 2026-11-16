//
//  ButtonClickService.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

/// Plays the shared tap sound for buttons and tab switches, honouring the button-sound setting.
@MainActor
final class ButtonClickService {
    private let guidanceAudioService: GuidanceAudioService
    private let audioService: SessionAudioService

    init(guidanceAudioService: GuidanceAudioService, audioService: SessionAudioService) {
        self.guidanceAudioService = guidanceAudioService
        self.audioService = audioService
    }

    func play() {
        guard UserDefaults.standard.object(forKey: PracticePreferences.buttonSounds) as? Bool ?? true else {
            return
        }

        // A tap sound never lands on top of narration from a running session.
        guard !audioService.isNarrating else {
            return
        }

        guidanceAudioService.playButtonClick()
    }
}
