//
//  FingerExampleView.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import SwiftUI

/// Chooses the example for a finger-session exercise: the rendered hand movie where one exists,
/// otherwise a native illustration.
struct FingerExampleView: View {
    let exercise: FingerExercise
    let phase: FingerPhase
    let returning: Bool
    let finger: Int
    let side: TrainingSide
    let paused: Bool

    var body: some View {
        if exercise == .forearmRotation {
            ForearmRotationExample(phase: phase, returning: returning, side: side, paused: paused)
        } else {
            FingerDemonstrationView(
                exercise: exercise, phase: phase, returning: returning,
                finger: finger, side: side, paused: paused
            )
        }
    }
}

/// Turns a hand about its vertical axis between the thumb-up start and a palm facing the viewer.
/// A native stand-in until a rendered forearm-rotation movie is bundled.
struct ForearmRotationExample: View {
    let phase: FingerPhase
    let returning: Bool
    let side: TrainingSide
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    private var startAngle: Double { 90 }
    private var palmAngle: Double { 0 }

    var body: some View {
        Image(systemName: "hand.raised.fill")
            .resizable()
            .scaledToFit()
            .padding(48)
            .foregroundStyle(TherapyPalette.ink)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(x: side == .left ? -1 : 1, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TherapyPalette.mediaBackground)
            .onAppear { restart() }
            .onChange(of: phase) { restart() }
            .onChange(of: returning) { restart() }
            .onChange(of: paused) { restart() }
    }

    private var angle: Double {
        turned ? palmAngle : startAngle
    }

    private var animates: Bool {
        !paused && !reduceMotion
    }

    private func restart() {
        switch phase {
        case .target:
            turned = true
        case .demonstration, .range:
            turned = false
            guard animates else {
                turned = true
                return
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                turned = true
            }
        case .active:
            let destination = !returning
            guard animates else {
                turned = destination
                return
            }
            withAnimation(.easeInOut(duration: 2)) {
                turned = destination
            }
        default:
            turned = false
        }
    }
}
