//
//  ExternalRotationDemonstrationView.swift
//  Itera
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
    /// The patient's arm choice; with both arms chosen, the right-arm recording plays beside its reflection.
    var selection: BalanceArmSelection?

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
            mirrored: selection != .both && (arm ?? selection?.initialArm) == .left,
            bothArms: selection == .both && exercise != .sitToStand,
            accessibilityKey: accessibilityKey
        )
    }
}
