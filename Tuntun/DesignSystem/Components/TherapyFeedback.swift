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
/// `animationDuration` is how long the circle eases toward each `intensity` sample; `paused`
/// stops its idle motion.
///
/// The page shows the cue, a comfort line and the circle, with underlined Pause and End text
/// actions at the bottom. Tapping elsewhere does nothing; Skip stays an accessibility action.
struct TMTherapyBreathingRest: View {
    let cue: LocalizedStringKey
    let intensity: Double
    var animationDuration = 0.25
    var paused = false
    let pause: () -> Void
    let stop: () -> Void
    var skip: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            heading

            TMTherapyBreathingCircle(
                intensity: intensity,
                paused: paused,
                smoothing: animationDuration
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 240, maxHeight: 240)
            .padding(.top, 56)
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            // Raised clear of the debug Skip rest control pinned to the bottom centre.
            TMTherapyRestActions(
                paused: paused,
                disablesPauseWhilePaused: true,
                pause: pause,
                stop: stop
            )
            .padding(.bottom, 96)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas.ignoresSafeArea())
        .accessibilityActions {
            if let skip {
                Button("rest.skip", action: skip)
            }
        }
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text(cue)
                .typography(size: 40, weight: .bold, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)

            Text("rest.breath.comfort")
                .typography(size: 24, weight: .regular, relativeTo: .title3)
                .foregroundStyle(TherapyPalette.muted)
        }
        .multilineTextAlignment(.center)
    }
}

/// Underlined Pause and End text actions at the bottom of a rest page. With
/// `disablesPauseWhilePaused`, Pause is disabled while paused (the pause dialog resumes);
/// otherwise it reads "Lanjutkan latihan" and resumes.
private struct TMTherapyRestActions: View {
    let paused: Bool
    var disablesPauseWhilePaused = false
    var tint: Color? = nil
    let pause: () -> Void
    let stop: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 24))

        layout {
            TMTherapyButton(
                title: showsResume ? "session.resumeExercise" : "session.pauseAction",
                symbol: showsResume ? "play.fill" : "pause.fill",
                disabled: disablesPauseWhilePaused && paused,
                plain: true,
                underlined: true,
                tint: tint,
                action: pause
            )
            .fixedSize()

            TMTherapyButton(
                title: "session.endAction",
                symbol: "stop.fill",
                plain: true,
                underlined: true,
                tint: tint,
                action: stop
            )
            .fixedSize()
        }
    }

    private var showsResume: Bool {
        paused && !disablesPauseWhilePaused
    }
}

/// Full-screen rest waves. The caller supplies the breathing cue and animation progress.
///
/// The page shows the centred cue and a comfort line over the waves, with underlined Pause (or
/// Resume) and End text actions at the bottom; tapping elsewhere does nothing. Paused, the cue
/// reads "Paused". `counter` (breaths remaining) is read to VoiceOver instead of drawn.
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
                .accessibilityHidden(true)

            heading
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Raised clear of the debug Skip rest control pinned to the bottom centre.
            TMTherapyRestActions(
                paused: paused,
                tint: TherapyPalette.onBrand,
                pause: togglePause,
                stop: stop
            )
            .padding(.bottom, 120)
        }
        .foregroundStyle(TherapyPalette.onBrand)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: paused)
    }

    private var heading: some View {
        VStack(spacing: 8) {
            ZStack {
                (paused ? Text("session.paused") : cue)
                    .typography(size: 40, weight: .bold, relativeTo: .largeTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .id(paused ? "session.paused" : cueID)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: cueID)

            Text("rest.breath.comfort")
                .typography(size: 24, weight: .regular, relativeTo: .title3)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(counter ?? Text(verbatim: ""))
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
            TMFrostedBackdrop()
        }
    }
}
