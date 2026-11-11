//
//  ExerciseExample.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct TMExerciseExample: View {
    let asset: ExerciseAnimationAsset
    let mirrored: Bool
    let mode: TherapyAnimationPlayback
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var failed = false
    @State private var ready = false

    var body: some View {
        ZStack {
            if !failed {
                TMExerciseVideoView(resource: asset.demonstrationResource, mode: mode, reducedMotion: reducedMotion) { event in
                    handle(event)
                }
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            }
            if failed {
                Text("session.animationFallback").padding()
            } else if !ready {
                ProgressView().accessibilityLabel(Text("session.loading"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("session.example"))
    }

    private func handle(_ event: ExerciseVideoEvent) {
        switch event {
        case .ready: ready = true
        case .failed: failed = true
        }
    }
}
