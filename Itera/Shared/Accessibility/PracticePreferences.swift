//
//  PracticePreferences.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

/// Presentation choices never change therapy timing or required voice readiness.
enum PracticePreferences {
    static let calmMode = "practice.calmMode"
    static let celebrationSounds = "practice.celebrationSounds"
    static let buttonSounds = "practice.buttonSounds"
    /// How Home and Progress address the patient. Stored only on this device; empty means no name.
    static let patientName = "practice.patientName"
    static let dailyPlanSide = "practice.dailyPlanSide"
    /// Whether key repetitions also keep a short video; off means skeleton replays only.
    /// On unless turned off.
    static let recordsRepClips = "practice.recordsRepClips"
    /// Whether clips pixelate faces and blur the room. Both on unless turned off.
    static let censorsFace = "practice.censorsFace"
    static let censorsBackground = "practice.censorsBackground"

    static var recordsRepClipsEnabled: Bool {
        UserDefaults.standard.object(forKey: recordsRepClips) as? Bool ?? true
    }

    static var repClipPrivacy: RepClipPrivacy {
        RepClipPrivacy(
            blursFace: UserDefaults.standard.object(forKey: censorsFace) as? Bool ?? true,
            blursBackground: UserDefaults.standard.object(forKey: censorsBackground) as? Bool ?? true
        )
    }
}
