//
//  ShoulderRotationMovieView.swift
//  Tuntun
//
//  Created by Fauzan Azima on 09/11/2026.
//

import SwiftUI

/// The bundled body example for one arm, looping silently, or moving to and holding the pose the
/// patient is asked for (`playback`). It stands in for the native illustration when a recording
/// exists for the exercise and arm.
struct TMShoulderRotationMovieView: View {
    let resource: String
    let paused: Bool
    var mirrored: Bool = false
    var playback: TherapyAnimationPlayback = .looping
    let timeline: DemonstrationTimeline
    var accessibilityKey: LocalizedStringKey = "rotation.animationAccessibility"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let holdsPose = paused || reduceMotion

        ZStack {
            TMExerciseVideoView(
                resource: resource,
                mode: playback,
                timeline: timeline,
                paused: paused,
                reducedMotion: reduceMotion
            ) { _ in
                // Bundled clips; a missing one leaves the framed background, as before.
            }
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)

            TMTherapyDemoCaption(paused: holdsPose)
        }
        .background(TherapyPalette.mediaBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(TherapyPalette.green.opacity(0.18), lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityKey)
    }
}
