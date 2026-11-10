//
//  TherapyCalmLoader.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import SwiftUI

/// A quiet waiting state: a softly breathing circle with a single calm line.
///
/// Use it instead of a spinner when the wait is expected and not an error. It holds still when
/// Reduce Motion is on.
struct TMTherapyCalmLoader: View {
    let title: LocalizedStringKey

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 32) {
            circle

            Text(title)
                .typography(.title3)
                .foregroundStyle(TherapyPalette.muted)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else {
                return
            }

            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                isExpanded = true
            }
        }
    }

    private var circle: some View {
        ZStack {
            Circle()
                .fill(TherapyPalette.mint.opacity(0.35))
                .frame(width: 160, height: 160)
                .scaleEffect(isExpanded ? 1 : 0.7)

            Circle()
                .fill(TherapyPalette.mint)
                .frame(width: 80, height: 80)
                .scaleEffect(isExpanded ? 1.1 : 0.9)
        }
        .accessibilityHidden(true)
    }
}
