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
    /// Loops, or moves to and holds the start or target pose, as during calibration and practice.
    var playback: TherapyAnimationPlayback = .looping

    /// The bundled recording for this exercise. Every arm clip shows the right arm and is
    /// reflected for the right arm, so the moving arm sits on the same side of the screen as the
    /// patient's own arm in the mirrored camera preview. Sit to stand is never reflected.
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

    /// The recording's rise and return, from the keyframes in `Tools/author_body_demonstrations.py`.
    /// The rotations start from the ready pose (elbow bent 90°) and sit to stand from the seat,
    /// so it sits down by playing the clip's opening stand-to-seat. Update these when a clip is
    /// re-exported with different timing.
    private var timeline: DemonstrationTimeline {
        switch exercise {
        case .crossMidline:
            return DemonstrationTimeline(riseFrames: 13...61, returnFrames: 67...109)
        case .externalRotation, .internalRotation:
            return DemonstrationTimeline(riseFrames: 49...79, returnFrames: 85...109)
        case .shoulderFlexion:
            return DemonstrationTimeline(riseFrames: 13...67, returnFrames: 73...121)
        case .sitToStand:
            return DemonstrationTimeline(riseFrames: 73...121, returnFrames: 13...37)
        }
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
            mirrored: exercise != .sitToStand && (arm ?? selection?.initialArm) == .right,
            playback: playback,
            timeline: timeline,
            accessibilityKey: accessibilityKey
        )
    }
}
