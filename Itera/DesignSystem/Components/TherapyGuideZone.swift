//
//  TherapyGuideZone.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import SwiftUI

/// A target zone drawn over the camera: a soft fill, a bold outline over a dark underlay, an icon
/// and an optional hold ring.
///
/// The zone fills whatever frame the caller gives it, so a caller can draw it as an ellipse that
/// matches a normalized acceptance region. It displays supplied values only; holds and timing stay
/// with the caller. An emphasized zone breathes with a halo outside its outline (frozen under
/// Reduce Motion); a quiet zone recedes so only the current step stands out.
struct TherapyGuideZone: View {
    let tint: Color
    let symbol: String
    /// Hold progress, 0...1. Nothing is drawn at 0.
    var progress = 0.0
    var emphasized = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            halo
            fill
            outline
            holdRing
            icon
        }
        .opacity(emphasized ? 1 : 0.55)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: emphasized)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Layers

    @ViewBuilder
    private var halo: some View {
        if emphasized {
            Ellipse()
                .stroke(tint.opacity(0.45), lineWidth: 6)
                .scaleEffect(breathing ? 1.1 : 1.02)
                .opacity(breathing ? 0.3 : 0.8)
        }
    }

    private var fill: some View {
        Ellipse().fill(tint.opacity(emphasized ? 0.3 : 0.12))
    }

    private var outline: some View {
        ZStack {
            Ellipse().stroke(TherapyPalette.calmUnderlay, lineWidth: emphasized ? 18 : 12)
            Ellipse().stroke(tint, lineWidth: emphasized ? 10 : 6)
        }
    }

    @ViewBuilder
    private var holdRing: some View {
        if progress > 0 {
            ZStack {
                Ellipse()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(TherapyPalette.calmUnderlay, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                Ellipse()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            }
            .padding(2)
        }
    }

    private var icon: some View {
        Image(systemName: symbol)
            .typography(size: 34, weight: .bold)
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(TherapyPalette.calmUnderlay, in: Circle())
            .overlay(Circle().stroke(tint, lineWidth: 4))
    }
}

#if DEBUG
#Preview("Guide zones") {
    HStack(spacing: 40) {
        TherapyGuideZone(tint: TherapyPalette.calmTeal, symbol: "hand.raised.fill", progress: 0.6)
            .frame(width: 180, height: 180)
        TherapyGuideZone(tint: TherapyPalette.calmBlue, symbol: "arrow.left", emphasized: false)
            .frame(width: 180, height: 180)
    }
    .padding(40)
    .background(.gray)
}
#endif
