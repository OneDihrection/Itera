//
//  TherapyDemoHighlight.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import SwiftUI

// MARK: - Demonstration step highlight

/// Calls attention to a demonstration panel whose content just moved to a new step.
///
/// Each change of `revision` draws a thin rust outline for about four seconds and pulses the
/// panel three times, gently: a faint ring ripples outward from the edge and fades while the
/// outline glows softly and the panel swells very slightly. The motion is the signal; there is no badge. `announcement` is
/// posted to VoiceOver. The first revision seen is the starting state and is never highlighted.
/// Under Reduce Motion only the static outline shows. The caller decides what counts as a new step.
struct TMTherapyDemoHighlight: ViewModifier {
    let revision: Int
    var announcement: String? = nil
    var cornerRadius: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shownRevision: Int?
    @State private var visible = false
    @State private var swelling = false
    /// 0 at the panel edge, 1 fully expanded and faded.
    @State private var ripple: CGFloat = 1

    private static var beatCount: Int { 3 }
    private static var swellSeconds: Double { 0.55 }
    private static var beatSeconds: Double { 1.1 }
    private static var swellScale: CGFloat { 1.01 }
    private static var visibleSeconds: Double { 4 }

    func body(content: Content) -> some View {
        content
            .scaleEffect(swelling ? Self.swellScale : 1)
            .overlay {
                if visible {
                    outline
                        .transition(.opacity)
                }
            }
            .task(id: revision) {
                await highlight()
            }
    }

    private var outline: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        return ZStack {
            TMTherapyDemoRipple(progress: ripple, cornerRadius: cornerRadius)

            shape
                .strokeBorder(TherapyPalette.calmUnderlay, lineWidth: 5)

            shape
                .strokeBorder(TherapyPalette.brand, lineWidth: 3)
                .shadow(color: TherapyPalette.brand.opacity(swelling ? 0.45 : 0), radius: 8)
        }
        .scaleEffect(swelling ? Self.swellScale : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Timing

    /// Runs one highlight; a newer revision cancels this task and starts its own.
    private func highlight() async {
        guard let previous = shownRevision else {
            shownRevision = revision
            return
        }

        guard previous != revision else {
            return
        }

        shownRevision = revision
        swelling = false
        ripple = 1

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            visible = true
        }

        if let announcement {
            AccessibilityNotification.Announcement(announcement).post()
        }

        var elapsed = 0.0

        if !reduceMotion {
            for _ in 0..<Self.beatCount {
                guard await beat() else {
                    return
                }

                elapsed += Self.beatSeconds
            }
        }

        guard await pause(max(0, Self.visibleSeconds - elapsed)) else {
            return
        }

        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) {
            visible = false
        }
    }

    /// One pulse: the ring restarts at the edge and ripples out over the whole beat while the
    /// outline glows and the panel swells for the first half. False when cancelled.
    private func beat() async -> Bool {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            ripple = 0
        }

        withAnimation(.easeOut(duration: Self.beatSeconds)) {
            ripple = 1
        }
        withAnimation(.easeOut(duration: Self.swellSeconds)) {
            swelling = true
        }
        guard await pause(Self.swellSeconds) else {
            return false
        }

        withAnimation(.easeIn(duration: Self.beatSeconds - Self.swellSeconds)) {
            swelling = false
        }
        return await pause(Self.beatSeconds - Self.swellSeconds)
    }

    /// False when the task was cancelled, so a replaced highlight stops changing state.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

/// The ring that ripples outward from the panel edge, thinning and fading as it grows.
/// Animatable so its stroke width and reach interpolate smoothly within each beat.
private struct TMTherapyDemoRipple: View, Animatable {
    var progress: CGFloat
    let cornerRadius: CGFloat

    private static var reach: CGFloat { 10 }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let spread = Self.reach * progress

        RoundedRectangle(cornerRadius: cornerRadius + spread)
            .strokeBorder(TherapyPalette.brand, lineWidth: 3 - 2 * progress)
            .opacity(0.55 * (1 - progress))
            .padding(-spread)
    }
}

extension View {
    /// Highlights this demonstration panel whenever `revision` changes. See `TMTherapyDemoHighlight`.
    func therapyDemoHighlight(
        revision: Int,
        announcement: String? = nil,
        cornerRadius: CGFloat = 24
    ) -> some View {
        modifier(
            TMTherapyDemoHighlight(
                revision: revision,
                announcement: announcement,
                cornerRadius: cornerRadius
            )
        )
    }
}
