//
//  TherapyGuideBubble.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMTherapyGuideBubble: View {
    let progress: Double
    let active: Bool
    var completionID: UUID? = nil
    var onCompletionPresented: (UUID) -> Void = { _ in }
    var showsTimer = false
    var diameter: CGFloat? = nil
    var outlineOnly = false
    /// Colour of the fill tint and progress arc. Finger guidance uses `guidanceOrange`.
    var tint: Color = TherapyPalette.guidanceBlue
    /// False draws only the progress arc, for a caller that draws the circle itself
    /// (`TMTherapyMergingGuide`): no fill and a clear track.
    var drawsBackground = true
    /// Plays `TMTherapyPopBurst` once each time a completed hold becomes visible.
    var popsOnCompletion = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var bursts = 0

    var body: some View {
        ZStack {
            if !outlineOnly && drawsBackground {
                Circle().fill(active ? tint.opacity(0.15) : TherapyPalette.surface.opacity(0.9))
            }
            if active || outlineOnly {
                TMTherapyProgressRing(
                    progress: showsTimer ? progress : 0,
                    lineWidth: ringWidth,
                    animatesProgress: progress < 1,
                    animationDuration: 0.2,
                    tint: tint,
                    track: drawsBackground ? .white.opacity(0.85) : .clear
                )
            }
            if popsOnCompletion {
                TMTherapyPopBurst(trigger: bursts, diameter: diameter ?? (active ? 108 : 72), tint: tint)
            }
        }
        .onChange(of: visibleCompletionID) { _, id in
            // The same visible-completion signal acknowledges the hold, so the pop and the
            // exercise's progression always agree.
            if popsOnCompletion, id != nil {
                bursts += 1
            }
        }
        .frame(width: diameter ?? (active ? 108 : 72), height: diameter ?? (active ? 108 : 72))
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
        let base: CGFloat = outlineOnly ? 20 : 14

        guard let diameter else {
            return base
        }

        return min(base, max(6, diameter * 0.17))
    }

    private var visibleCompletionID: UUID? {
        guard active, showsTimer, progress >= 1, scenePhase == .active else {
            return nil
        }
        return completionID
    }
}
