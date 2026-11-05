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
}
