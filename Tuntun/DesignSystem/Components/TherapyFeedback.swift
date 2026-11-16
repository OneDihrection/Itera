//
//  TherapyFeedback.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMTherapyProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 12
    var animatesProgress = true
    var animationDuration = 0.12
    var tint: Color = TherapyPalette.primary
    /// Defaults to a faint version of `tint`.
    var track: Color? = nil
    var lineCap: CGLineCap = .round
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(track ?? tint.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion || !animatesProgress ? nil : .linear(duration: animationDuration), value: progress)
        }
        .accessibilityElement()
        .accessibilityLabel("session.holdProgress")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// A breathing cue driven by the rest clock. The session owns narration and timing.
struct TMTherapyBreathingRest: View {
    let cue: LocalizedStringKey
    let intensity: Double
    var animationDuration = 0.15
    let pause: () -> Void
    let stop: () -> Void
    var skip: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Text(cue)
                    .typography(size: 40, weight: .bold, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("rest.breath.comfort")
                    .typography(size: 24, weight: .regular, relativeTo: .title3)
                    .foregroundStyle(TherapyPalette.muted)
            }
            .multilineTextAlignment(.center)

            GeometryReader { geometry in
                let diameter = min(400, geometry.size.width, geometry.size.height)
                Circle()
                    .fill(TherapyPalette.planPanel.opacity(0.35))
                    .overlay {
                        Circle()
                            .strokeBorder(TherapyPalette.brand, lineWidth: diameter * 0.18)
                            .opacity(reduceMotion ? 1 : intensity)
                    }
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(reduceMotion ? 1 : 0.76 + 0.24 * (intensity - 0.25) / 0.75)
                    .animation(reduceMotion ? nil : .linear(duration: animationDuration), value: intensity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            .frame(maxHeight: 400)

            Spacer(minLength: 0)

            HStack(spacing: 20) {
                TMTherapyTextButton(title: "session.pauseAction", symbol: "pause.fill", action: pause)
                if let skip {
                    TMTherapyTextButton(title: "rest.skip", symbol: "forward.end", action: skip)
                }
                TMTherapyTextButton(title: "session.endAction", symbol: "stop.fill", action: stop)
            }
        }
        .padding(24)
        .foregroundStyle(TherapyPalette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas.ignoresSafeArea())
    }
}

/// Full-screen rest waves. The caller supplies the breathing cue and animation progress.
struct TMTherapyLongRest: View {
    let cue: Text
    let cueID: String
    let counter: Text?
    let intensity: Double
    let paused: Bool
    let togglePause: () -> Void
    let stop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            TMTherapyLongRestWaves(intensity: intensity, paused: paused)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let counter {
                    counter.typography(.title3)
                }
                ZStack {
                    (paused ? Text("session.paused") : cue)
                        .typography(size: 40, weight: .bold, relativeTo: .largeTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .id(paused ? "session.paused" : cueID)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: cueID)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 24) {
                Button(paused ? "session.resume" : "session.pause", action: togglePause)
                Button("session.endAction", action: stop)
            }
            .typography(.headline)
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(24)
        }
        .foregroundStyle(.white)
    }
}

/// The final countdown overlays the mounted practice layout.
struct TMPracticeCountdown: View {
    let seconds: Int
    var title: LocalizedStringKey = "calibration.countdown"
    let pause: () -> Void
    let stop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            Button(action: pause) {
                VStack(spacing: 12) {
                    Text(title)
                        .typography(size: 32, weight: .bold, relativeTo: .title)
                        .multilineTextAlignment(.center)

                    Text(seconds, format: .number)
                        .typography(size: min(240, geometry.size.height * 0.36), weight: .bold, relativeTo: .largeTitle)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: seconds)
                }
                .padding(24)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(seconds, format: .number))
            .accessibilityHint("countdown.pauseHint")
            .accessibilityAction(named: Text("action.end"), stop)
        }
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.5))
                .ignoresSafeArea()
        }
    }
}
