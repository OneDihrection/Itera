//
//  TherapyGuideBubble.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TherapyGuideBubble: View {
    let label: String
    let remaining: Double
    let progress: Double
    let active: Bool
    let reached: Bool
    var completionID: UUID? = nil
    var onCompletionPresented: (UUID) -> Void = { _ in }
    var showsTimer = false
    /// Draws the number and "Tahan" inside the circle. Turn off when a separate readout
    /// sits beside the hand; the ring and completion acknowledgment keep working.
    var showsTimerText = true
    var diameter: CGFloat? = nil
    var outlineOnly = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !outlineOnly {
                Circle().fill(active || reached ? TherapyPalette.secondary : TherapyPalette.surface.opacity(0.9))
            }
            if active || outlineOnly {
                TherapyProgressRing(
                    progress: showsTimer ? progress : 0,
                    lineWidth: ringWidth,
                    animatesProgress: progress < 1,
                    animationDuration: 0.2
                )
            }
            content
        }
        .frame(width: diameter ?? (active ? 108 : 72), height: diameter ?? (active ? 108 : 72))
        .overlay(alignment: .bottom) {
            if showsTimer && showsTimerText {
                Text("guide.hold").typography(.headline)
                    .padding(.horizontal, 8)
                    .background(TherapyPalette.surface, in: Capsule())
                    .offset(y: outlineOnly ? -12 : 36)
            }
        }
        .foregroundStyle(TherapyPalette.primary)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: reached)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: visibleCompletionID) {
            guard let id = visibleCompletionID else {
                return
            }
            // This confirms a visible completed cue; it never credits exercise time.
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled, visibleCompletionID == id else {
                return
            }
            onCompletionPresented(id)
        }
    }

    /// Thinner rings for the smaller circles of a hand far from the camera.
    private var ringWidth: CGFloat {
        let base: CGFloat = outlineOnly ? 14 : 10

        guard let diameter else {
            return base
        }

        return min(base, max(5, diameter * 0.11))
    }

    // Zero belongs only to a completed ring, never a rounded partial hold.
    private var displayedRemaining: Double {
        max(0, ceil(remaining * 10) / 10)
    }

    private var visibleCompletionID: UUID? {
        guard active, showsTimer, progress >= 1, scenePhase == .active else {
            return nil
        }
        return completionID
    }

    @ViewBuilder
    private var content: some View {
        if showsTimer && showsTimerText {
            VStack(spacing: 0) {
                Text(displayedRemaining, format: .number.precision(.fractionLength(1)))
                    .typography(size: outlineOnly ? 52 : 32, weight: .bold, relativeTo: .title)
                    .monospacedDigit()
                Text("guide.secondsUnit").typography(.caption)
                if reached {
                    Image(systemName: "checkmark").typography(.caption)
                }
            }
            .padding(outlineOnly ? 12 : 0)
            .background(outlineOnly ? TherapyPalette.surface.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 12))
        } else if reached {
            Image(systemName: "checkmark").typography(.title2)
        } else if !label.isEmpty {
            Text(verbatim: label).typography(.title2)
        }
    }
}
