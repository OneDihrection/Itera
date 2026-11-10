//
//  FingerExampleView.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import SwiftUI

/// Chooses the example for a finger-session exercise: the rendered hand movie where one exists,
/// otherwise a native illustration.
struct TMFingerExampleView: View {
    let exercise: FingerExercise
    let phase: FingerPhase
    let returning: Bool
    let finger: Int
    let side: TrainingSide
    let paused: Bool

    var body: some View {
        if exercise == .forearmRotation {
            TMHandRotationExample(phase: phase, returning: returning, side: side, paused: paused)
        } else {
            TMFingerDemonstrationView(
                exercise: exercise, phase: phase, returning: returning,
                finger: finger, side: side, paused: paused
            )
        }
    }
}
