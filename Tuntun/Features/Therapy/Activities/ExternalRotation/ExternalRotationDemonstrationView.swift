//
//  ExternalRotationDemonstrationView.swift
//  Tuntun
//
//  Created by Fauzan Azima on 03/11/2026.
//

import SwiftUI

/// Chooses the rendered demonstration for each body exercise.
struct TMBalanceExerciseDemonstrationView: View {
    let exercise: BalanceExercise
    let paused: Bool
    /// The arm being exercised, which picks the recording for that arm.
    var arm: CrossingArm?
    /// The patient's arm choice; with both arms chosen, the demonstration follows the active arm.
    var selection: BalanceArmSelection?
    /// Holds the target pose instead of looping, as during practice.
    var holdsPeak = false

    /// The bundled recording for this exercise; every arm clip shows the right arm.
    private var movieResource: String {
        switch exercise {
        case .crossMidline:
            return "cross_midline_right_demonstration"
        case .externalRotation:
            return "shoulder_external_rotation_right_demonstration"
        case .internalRotation:
            return "shoulder_internal_rotation_right_demonstration"
        case .shoulderFlexion:
            return "shoulder_flexion_right_demonstration"
        case .sitToStand:
            return "sit_to_stand_demonstration"
        }
    }

    /// Seconds into the recording where the target pose is held, at the middle of its keyframed
    /// hold in `Tools/author_body_demonstrations.py` (24 FPS, frame 1 at zero). Sit to stand
    /// holds the standing pose. Update these when a clip is re-exported with different timing.
    private var peakSeconds: Double {
        let frame: Double

        switch exercise {
        case .crossMidline:
            frame = 61
        case .externalRotation, .internalRotation:
            frame = 79
        case .shoulderFlexion:
            frame = 67
        case .sitToStand:
            frame = 121
        }

        return (frame - 1) / 24
    }

    private var accessibilityKey: LocalizedStringKey {
        switch exercise {
        case .crossMidline:
            return "balance.animationAccessibility"
        case .externalRotation:
            return "rotation.animationAccessibility"
        case .internalRotation:
            return "internalRotation.animationAccessibility"
        case .shoulderFlexion:
            return "shoulderFlexion.animationAccessibility"
        case .sitToStand:
            return "sitToStand.animationAccessibility"
        }
    }

    var body: some View {
        movie(movieResource, accessibilityKey: accessibilityKey)
    }

    private func movie(_ resource: String, accessibilityKey: LocalizedStringKey) -> some View {
        TMShoulderRotationMovieView(
            resource: resource,
            paused: paused,
            mirrored: (arm ?? selection?.initialArm) == .left,
            holdsPeakAt: holdsPeak ? peakSeconds : nil,
            accessibilityKey: accessibilityKey
        )
    }
}
