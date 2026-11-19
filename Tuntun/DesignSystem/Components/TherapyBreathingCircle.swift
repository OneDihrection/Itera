//
//  TherapyBreathingCircle.swift
//  Tuntun
//
//  Created by dimaswisodewo on 19/11/2026.
//

import SwiftUI

/// The short rest's breathing circle, drawn by the `breathingCircle` Metal shader.
///
/// The caller publishes `intensity` (0.25 at rest, 1 at a full breath) at its own sampling rate;
/// the breath is interpolated over `smoothing` seconds toward each sample and rendered every
/// display frame (capped at 60 fps), so the circle swells and settles continuously. Inhale grows
/// the circle, strengthens and brightens its rust ring and swells a faint halo; exhale reverses it.
/// The edge wobbles gently on a clock that stops while `paused`. Reduce Motion draws a still,
/// full-strength circle.
struct TMTherapyBreathingCircle: View {
    let intensity: Double
    var paused = false
    var smoothing = 0.25

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = ShaderMotionClock()

    private var isMoving: Bool {
        !paused && !reduceMotion
    }

    /// 0 at rest, 1 at a full breath. Reduce Motion keeps the former static look: full size and
    /// full-strength ring.
    private var expansion: Double {
        guard !reduceMotion else {
            return 1
        }

        return min(1, max(0, (intensity - 0.25) / 0.75))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isMoving)) { timeline in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.white)
                    .modifier(
                        BreathingCircleShader(
                            size: geometry.size,
                            time: clock.time(at: timeline.date),
                            expansion: expansion,
                            ring: TherapyPalette.brand,
                            fill: TherapyPalette.planPanel
                        )
                    )
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: smoothing), value: expansion)
        .onChange(of: isMoving, initial: true) { _, moving in
            if moving {
                clock.resume(at: .now)
            } else {
                clock.pause(at: .now)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shader

/// Applies the circle shader with an animatable expansion, so SwiftUI interpolates it per frame.
private struct BreathingCircleShader: ViewModifier, Animatable {
    let size: CGSize
    let time: Double
    var expansion: Double
    let ring: Color
    let fill: Color

    var animatableData: Double {
        get { expansion }
        set { expansion = newValue }
    }

    func body(content: Content) -> some View {
        content.colorEffect(
            ShaderLibrary.breathingCircle(
                .float2(size),
                .float(time),
                .float(expansion),
                .color(ring),
                .color(fill)
            )
        )
    }
}

#Preview {
    TimelineView(.animation) { timeline in
        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 9)
        let fraction = phase < 6 ? phase / 6 : 1 - (phase - 6) / 3
        let intensity = 0.25 + 0.75 * (1 - cos(fraction * .pi)) / 2

        TMTherapyBreathingCircle(intensity: intensity)
            .frame(width: 400, height: 400)
    }
    .padding()
    .background(TherapyPalette.canvas)
}
