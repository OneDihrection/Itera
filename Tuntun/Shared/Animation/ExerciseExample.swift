//
//  ExerciseExample.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct TMExerciseExample: View {
    let asset: ExerciseAnimationAsset
    let mirrored: Bool
    let mode: TherapyAnimationPlayback
    /// The reach clip's pose to hold (see `ExerciseAnimationAsset.peakSeconds(reachPose:)`).
    var reachPose = 0
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var failed = false

    var body: some View {
        ZStack {
            if !failed {
                TMExerciseVideoView(
                    resource: asset.demonstrationResource,
                    mode: mode,
                    peakSeconds: asset.peakSeconds(reachPose: reachPose),
                    reducedMotion: reducedMotion
                ) { event in
                    handle(event)
                }
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            }
            // No loading indicator: the clip is bundled, and a spinner would sit on top of it.
            if failed {
                Text("session.animationFallback").padding()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("session.example"))
    }

    private func handle(_ event: ExerciseVideoEvent) {
        switch event {
        case .ready: break
        case .failed: failed = true
        }
    }
}
