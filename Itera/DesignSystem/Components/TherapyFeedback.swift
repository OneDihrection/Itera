//
//  TherapyFeedback.swift
//  Itera
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
            Color(red: 0.50, green: 0.16, blue: 0.05)
                .overlay {
                    Canvas { context, size in
                        let rise = reduceMotion ? 0 : CGFloat(intensity - 0.25) * size.height * 0.14
                        let colors = [
                            Color(red: 0.63, green: 0.19, blue: 0.06),
                            Color(red: 0.72, green: 0.22, blue: 0.05),
                            Color(red: 0.82, green: 0.26, blue: 0.04)
                        ]
                        for (index, color) in colors.enumerated() {
                            let edge = size.height * (0.28 + CGFloat(index) * 0.23) - rise
                            var wave = Path()
                            wave.move(to: CGPoint(x: 0, y: edge))
                            wave.addQuadCurve(
                                to: CGPoint(x: size.width, y: edge),
                                control: CGPoint(x: size.width / 2, y: edge - size.height * 0.14)
                            )
                            wave.addLine(to: CGPoint(x: size.width, y: size.height))
                            wave.addLine(to: CGPoint(x: 0, y: size.height))
                            wave.closeSubpath()
                            context.fill(wave, with: .color(color))
                        }
                    }
                    .accessibilityHidden(true)
                }
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
    let pause: () -> Void
    let stop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            Button(action: pause) {
                VStack(spacing: 12) {
                    Text("calibration.countdown")
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
            .accessibilityLabel("calibration.countdown")
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

/// A large countdown digit inside a thick ring that sweeps continuously.
///
/// Owners publish whole seconds. While `running`, the ring animates linearly to the next second's
/// value over exactly one second, so it moves smoothly instead of stepping. When the clock is not
/// running yet (a cue is still being spoken) or has been reset, the ring rests full with no
/// animation, so it never moves ahead of the digit.
struct TMTherapyCountdownDial: View {
    let secondsLeft: Int
    let total: Int
    /// False while the countdown is waiting to start; the ring then holds its full value.
    var running = true
    var tint: Color = TherapyPalette.primary
    var track: Color = TherapyPalette.secondary
    var unit: LocalizedStringKey? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set after the first render, so a dial that appears already running still starts from this
    /// second's value and sweeps, instead of starting one second ahead.
    @State private var armed = false

    var body: some View {
        GeometryReader { geometry in
            let diameter = max(120, min(geometry.size.width, geometry.size.height) * 0.94)
            let lineWidth = diameter * 0.06

            ZStack {
                Circle().stroke(track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: target)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .animation(running && armed ? .linear(duration: 1) : nil, value: target)

                VStack(spacing: 0) {
                    Text(verbatim: String(max(0, secondsLeft)))
                        .typography(size: diameter * 0.46, weight: .bold, relativeTo: .largeTitle)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    if let unit {
                        Text(unit)
                            .typography(size: diameter * 0.075, weight: .medium, relativeTo: .title2)
                            .foregroundStyle(TherapyPalette.muted)
                    }
                }
                .foregroundStyle(TherapyPalette.ink)
                .padding(lineWidth * 1.5)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { armed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("stage.countdown"))
        .accessibilityValue(Text(verbatim: String(max(0, secondsLeft))))
    }

    /// The value the ring is heading for: the end of the current second while running, otherwise
    /// the start of it.
    private var target: Double {
        let remaining = running && armed ? secondsLeft - 1 : secondsLeft

        return min(1, max(0, Double(remaining) / Double(max(1, total))))
    }
}

/// A bounded, deterministic burst; Reduce Motion keeps the success symbol without moving particles.
struct TMTherapyCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var burstFinished = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: burstFinished)) { timeline in
                    Canvas { context, size in
                        let elapsed = timeline.date.timeIntervalSince(started)
                        guard elapsed < 2.4 else {
                            return
                        }
                        let colors = [TherapyPalette.primary, TherapyPalette.secondary, TherapyPalette.tertiary]
                        for index in 0..<32 {
                            let angle = Double(index) * 2.399
                            let speed = 80 + Double(index % 7) * 23
                            let x = size.width / 2 + cos(angle) * speed * elapsed
                            let y = size.height * 0.35 + sin(angle) * speed * elapsed + 85 * elapsed * elapsed
                            context.opacity = max(0, 1 - elapsed / 2.4)
                            context.fill(
                                Path(roundedRect: CGRect(x: x, y: y, width: 10, height: 16), cornerRadius: 3),
                                with: .color(colors[index % colors.count])
                            )
                        }
                    }
                }
            }
            Image(systemName: "checkmark.seal.fill")
                .accessibilityHidden(true)
                .typography(size: 100, weight: .bold)
                .foregroundStyle(TherapyPalette.primary)
                .padding(30)
                .background(TherapyPalette.secondary, in: Circle())
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(2.4))
            burstFinished = true
        }
    }
}

struct TMTherapyFeelingChoice: View {
    let title: LocalizedStringKey
    /// -1 is difficult, 0 is just right, 1 is easy.
    let expression: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 26) {
                face.frame(width: 112, height: 112)
                Text(title).typography(.title2)
            }
            .foregroundStyle(selected ? TherapyPalette.primary : TherapyPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 260)
            .padding(18)
            .background(selected ? TherapyPalette.secondary : TherapyPalette.surface,
                        in: RoundedRectangle(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(selected ? TherapyPalette.primary : TherapyPalette.muted.opacity(0.3),
                            lineWidth: selected ? 4 : 1)
            }
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var face: some View {
        Canvas { context, size in
            let color = selected ? TherapyPalette.primary : TherapyPalette.ink
            context.stroke(Path(ellipseIn: CGRect(x: 5, y: 5, width: 102, height: 102)),
                           with: .color(color), lineWidth: 7)
            for x in [38.0, 74.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 6, y: 38, width: 12, height: 14)), with: .color(color))
            }
            var mouth = Path()
            let edge = expression < 0 ? 84.0 : 74.0
            let control: Double
            switch expression {
            case ..<0: control = 51
            case 1...: control = 103
            default: control = 74
            }
            mouth.move(to: CGPoint(x: 32, y: edge))
            mouth.addQuadCurve(to: CGPoint(x: 80, y: edge), control: CGPoint(x: 56, y: control))
            context.stroke(mouth, with: .color(color), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
