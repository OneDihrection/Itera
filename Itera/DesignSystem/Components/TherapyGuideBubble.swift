//
//  TherapyGuideBubble.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TherapyGuideBubble: View {
    let progress: Double
    let active: Bool
    var completionID: UUID? = nil
    var onCompletionPresented: (UUID) -> Void = { _ in }
    var showsTimer = false
    var diameter: CGFloat? = nil
    var outlineOnly = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if !outlineOnly {
                Circle().fill(active ? TherapyPalette.guidanceBlue.opacity(0.15) : TherapyPalette.surface.opacity(0.9))
            }
            if active || outlineOnly {
                TherapyProgressRing(
                    progress: showsTimer ? progress : 0,
                    lineWidth: ringWidth,
                    animatesProgress: progress < 1,
                    animationDuration: 0.2,
                    tint: TherapyPalette.guidanceBlue,
                    track: .white.opacity(0.85)
                )
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
