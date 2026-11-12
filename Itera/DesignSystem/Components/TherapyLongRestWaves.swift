//
//  TherapyLongRestWaves.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import SwiftUI

/// Full-screen rust waves for the long breathing rest, drawn by the `longRestWaves` Metal shader.
///
/// The caller publishes `intensity` (0.25 at rest, 1 at a full breath) at its own sampling rate;
/// the breath is interpolated between samples and rendered every display frame (capped at
/// 60 fps), so the waves move continuously. Inhale lifts and fans the bands apart, swells their
/// crests and brightens them slightly; exhale reverses it. The crests also sway slowly on a clock that stops while
/// `paused`, so resuming never jumps. Reduce Motion draws static waves at rest height.
struct TMTherapyLongRestWaves: View {
    let intensity: Double
    let paused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = SwayClock()

    private static let base = Color(red: 0.50, green: 0.16, blue: 0.05)
    private static let bands = [
        Color(red: 0.63, green: 0.19, blue: 0.06),
        Color(red: 0.72, green: 0.22, blue: 0.05),
        Color(red: 0.82, green: 0.26, blue: 0.04)
    ]

    /// Slightly longer than the long rest's 80 ms sampling, so a late sample never leaves the
    /// waves standing still.
    private static let expansionSmoothing = 0.12

    private var isMoving: Bool {
        !paused && !reduceMotion
    }

    /// 0 at rest, 1 at a full breath; the shader turns it into lift, crest swell and brightening.
    private var expansion: Double {
        guard !reduceMotion else {
            return 0
        }

        return min(1, max(0, (intensity - 0.25) / 0.75))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isMoving)) { timeline in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Self.base)
                    .modifier(
                        LongRestWaveShader(
                            size: geometry.size,
                            time: clock.time(at: timeline.date),
                            expansion: expansion,
                            base: Self.base,
                            bands: Self.bands
                        )
                    )
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: Self.expansionSmoothing), value: expansion)
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

/// Applies the wave shader with an animatable expansion, so SwiftUI interpolates it per frame.
private struct LongRestWaveShader: ViewModifier, Animatable {
    let size: CGSize
    let time: Double
    var expansion: Double
    let base: Color
    let bands: [Color]

    var animatableData: Double {
        get { expansion }
        set { expansion = newValue }
    }

    func body(content: Content) -> some View {
        content.colorEffect(
            ShaderLibrary.longRestWaves(
                .float2(size),
                .float(time),
                .float(expansion),
                .color(base),
                .color(bands[0]),
                .color(bands[1]),
                .color(bands[2])
            )
        )
    }
}

// MARK: - Sway clock

/// Seconds of sway motion, excluding time spent paused.
private struct SwayClock {
    private var accumulated = 0.0
    private var runningSince: Date?

    mutating func resume(at date: Date) {
        guard runningSince == nil else {
            return
        }

        runningSince = date
    }

    mutating func pause(at date: Date) {
        guard let runningSince else {
            return
        }

        accumulated += max(0, date.timeIntervalSince(runningSince))
        self.runningSince = nil
    }

    func time(at date: Date) -> Double {
        guard let runningSince else {
            return accumulated
        }

        return accumulated + max(0, date.timeIntervalSince(runningSince))
    }
}
