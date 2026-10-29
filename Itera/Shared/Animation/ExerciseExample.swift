//
//  ExerciseExample.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import RealityKit
import SwiftUI

struct ExerciseExample: View {
    let asset: ExerciseAnimationAsset
    let mirrored: Bool
    let mode: TherapyAnimationPlayback
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var failed = false
    @State private var ready = false

    var body: some View {
        ZStack {
            if !failed {
                AnimationViewport(asset: asset, mode: mode, reducedMotion: reducedMotion) { event in
                    switch event {
                    case .ready: ready = true
                    case .failed: failed = true
                    }
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
}

private struct AnimationViewport: UIViewRepresentable {
    let asset: ExerciseAnimationAsset
    let mode: TherapyAnimationPlayback
    let reducedMotion: Bool
    let onEvent: (ExerciseAnimationRenderer.Event) -> Void

    func makeCoordinator() -> ExerciseAnimationRenderer { ExerciseAnimationRenderer() }
    func makeUIView(context: Context) -> ARView { context.coordinator.view }
    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.configure(
            exercise: asset, reducedMotion: reducedMotion, mode: mode, requestID: nil,
            onEvent: onEvent)
    }
    static func dismantleUIView(_ view: ARView, coordinator: ExerciseAnimationRenderer) {
        coordinator.stop()
    }
}
