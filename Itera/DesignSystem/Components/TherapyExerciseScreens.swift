//
//  TherapyExerciseScreens.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

// The five screens every exercise shares: intro, live practice, pause, set done and all done.
// They take values, content and actions only; sessions keep their own timing and progression.

// MARK: - Heading

/// Grey "Latihan 1" above the exercise title, centred.
struct TherapyExerciseHeading: View {
    var eyebrow: Text? = nil
    let title: Text

    var body: some View {
        VStack(spacing: 4) {
            if let eyebrow {
                eyebrow
                    .typography(size: 22, weight: .regular, relativeTo: .title3)
                    .foregroundStyle(TherapyPalette.muted)
            }

            title
                .typography(size: 42, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(TherapyPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stats

/// A large rust number with its unit beside it, such as "8 Repetisi".
struct TherapyTargetStat: View {
    let value: Int
    let unit: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(value, format: .number)
                .typography(size: 64, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(TherapyPalette.brand)
            unit
                .typography(size: 30, weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Repetisi 3 / 8": a label, the current value in rust and the total in grey.
struct TherapyProgressStat: View {
    let label: Text
    let value: Int
    let total: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            label
                .typography(size: 30, weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value, format: .number)
                    .typography(size: 56, weight: .bold, relativeTo: .largeTitle)
                    .foregroundStyle(TherapyPalette.brand)
                Text(verbatim: "/ \(total)")
                    .typography(size: 48, weight: .regular, relativeTo: .largeTitle)
                    .foregroundStyle(TherapyPalette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stats side by side with a thin divider between them.
struct TherapyStatRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 36) {
            content
        }
    }
}

/// The thin vertical divider used between stats.
struct TherapyStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(TherapyPalette.outline)
            .frame(width: 1.5, height: 64)
            .accessibilityHidden(true)
    }
}

// MARK: - Instruction bubble

/// A white rounded bubble for the live cue, placed at the bottom of the camera.
struct TherapyInstructionBubble: View {
    let text: Text

    var body: some View {
        text
            .typography(size: 24, weight: .medium, relativeTo: .title3)
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Back

/// The rust "‹ Kembali" text action at the top of the intro.
struct TherapyBackButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                Text(title)
            }
            .typography(size: 24, weight: .semiBold, relativeTo: .title3)
            .foregroundStyle(TherapyPalette.brand)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TherapySoundButtonStyle())
    }
}

// MARK: - Intro

/// The page before an exercise: what it trains, the target, a safety note and Start.
struct TherapyExerciseIntro<Media: View, Targets: View>: View {
    let heading: TherapyExerciseHeading
    let focusTitle: LocalizedStringKey
    let focus: Text
    let targetTitle: LocalizedStringKey
    let safetyNote: LocalizedStringKey
    let startTitle: LocalizedStringKey
    var startDisabled = false
    var message: Text? = nil
    let onBack: () -> Void
    let onStart: () -> Void
    @ViewBuilder let media: Media
    @ViewBuilder let targets: Targets

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack {
                    TherapyBackButton(title: "action.back", action: onBack)
                    Spacer()
                }

                heading

                content

                safety

                if let message {
                    message
                        .typography(.footnote)
                        .foregroundStyle(TherapyPalette.muted)
                        .multilineTextAlignment(.center)
                }

                TherapyButton(
                    title: startTitle,
                    symbol: "play.fill",
                    disabled: startDisabled,
                    prominent: true,
                    action: onStart
                )
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
        }
        .background(TherapyPalette.canvas)
    }

    @ViewBuilder
    private var content: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 32))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 56))

        layout {
            media
                .frame(maxWidth: 420, minHeight: 340, maxHeight: 400)
                .frame(maxWidth: .infinity)
                .background(TherapyPalette.planPanel, in: RoundedRectangle(cornerRadius: 32))
                .clipShape(RoundedRectangle(cornerRadius: 32))

            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(focusTitle)
                .typography(size: 30, weight: .bold, relativeTo: .title2)
                .accessibilityAddTraits(.isHeader)

            focus
                .typography(size: 26, weight: .regular, relativeTo: .title3)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(TherapyPalette.outline)
                .frame(height: 1)
                .padding(.vertical, 8)

            Text(targetTitle)
                .typography(size: 22, weight: .semiBold, relativeTo: .headline)
                .foregroundStyle(TherapyPalette.muted)

            targets
        }
        .foregroundStyle(TherapyPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var safety: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(TherapyPalette.brand)
            Text(safetyNote)
                .foregroundStyle(TherapyPalette.muted)
        }
        .typography(size: 20, weight: .regular, relativeTo: .callout)
        .padding(.vertical, 14)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(TherapyPalette.planCard, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Live practice

/// The practice screen: heading, the camera with its cue bubble, the demonstration column,
/// repetition and set counters, and Pause and End.
///
/// The camera keeps one position in this view for every state, so callers can layer stage
/// pages and dialogs over it without remounting the preview.
struct TherapyExerciseLiveLayout<Camera: View, Demo: View, Accessories: View>: View {
    let heading: TherapyExerciseHeading
    var cue: Text? = nil
    let demoTitle: LocalizedStringKey
    let repetitions: (done: Int, goal: Int)
    var sets: (number: Int, total: Int)? = nil
    let pauseTitle: LocalizedStringKey
    let endTitle: LocalizedStringKey
    var pauseDisabled = false
    let onPause: () -> Void
    let onEnd: () -> Void
    @ViewBuilder let camera: Camera
    @ViewBuilder let demo: Demo
    /// Small trailing controls beside the heading, such as music or voice.
    @ViewBuilder let accessories: Accessories

    var body: some View {
        VStack(spacing: 24) {
            heading
                .overlay(alignment: .trailing) {
                    HStack(spacing: 12) {
                        accessories
                    }
                }

            HStack(alignment: .top, spacing: 32) {
                cameraArea
                demoColumn
                    .frame(width: 380)
            }
            .frame(maxHeight: .infinity)

            HStack(alignment: .center, spacing: 32) {
                stats
                Spacer(minLength: 0)
                controls
                    .frame(width: 380)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(TherapyPalette.canvas)
    }

    private var cameraArea: some View {
        camera
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(alignment: .bottom) {
                if let cue {
                    TherapyInstructionBubble(text: cue)
                        .padding(24)
                }
            }
    }

    private var demoColumn: some View {
        VStack(spacing: 16) {
            Text(demoTitle)
                .typography(size: 24, weight: .bold, relativeTo: .title3)
                .foregroundStyle(TherapyPalette.ink)

            demo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private var stats: some View {
        TherapyStatRow {
            TherapyProgressStat(
                label: Text("exercise.repetitionsUnit"),
                value: repetitions.done,
                total: repetitions.goal
            )

            if let sets {
                TherapyStatDivider()
                TherapyProgressStat(
                    label: Text("exercise.setsUnit"),
                    value: sets.number,
                    total: sets.total
                )
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            TherapyButton(
                title: pauseTitle,
                symbol: "pause.fill",
                disabled: pauseDisabled,
                pill: true,
                brand: true,
                action: onPause
            )
            TherapyButton(
                title: endTitle,
                symbol: "stop.fill",
                secondary: true,
                pill: true,
                action: onEnd
            )
        }
    }
}

// MARK: - Pause dialog

/// "Latihan dijeda" over a frosted copy of the session, with practice time so far.
/// Ending asks once more inside the card before calling `onEnd`.
struct TherapyPauseDialog<Extra: View>: View {
    var setLabel: Text? = nil
    let title: Text
    let elapsedSeconds: Int
    var resumeDisabled = false
    var status: Text? = nil
    let onEnd: () -> Void
    let onResume: () -> Void
    /// Caregiver recovery actions, shown under a disclosure so the dialog stays calm.
    @ViewBuilder let extra: Extra

    @State private var confirmingEnd = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.25))
                .ignoresSafeArea()
                .accessibilityHidden(true)

            card
                .frame(maxWidth: 680)
                .padding(40)
        }
    }

    private var card: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    Image(systemName: "pause.fill")
                        .typography(size: 20, weight: .bold)
                        .foregroundStyle(TherapyPalette.brand)
                        .frame(width: 48, height: 48)
                        .background(TherapyPalette.planPanel, in: Circle())
                        .accessibilityHidden(true)
                    Text("session.pausedTitle")
                        .typography(size: 36, weight: .bold, relativeTo: .title)
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(spacing: 4) {
                    if let setLabel {
                        setLabel
                            .typography(size: 22, weight: .regular, relativeTo: .title3)
                            .foregroundStyle(TherapyPalette.muted)
                    }
                    title
                        .typography(size: 22, weight: .medium, relativeTo: .title3)
                }

                Text(Self.clock(elapsedSeconds))
                    .typography(size: 72, weight: .bold, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .accessibilityLabel(Text("session.elapsedTime \(elapsedSeconds / 60) \(elapsedSeconds % 60)"))

                if let status {
                    status
                        .typography(.footnote)
                        .foregroundStyle(TherapyPalette.muted)
                }

                actions

                extra
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(TherapyPalette.ink)
            .padding(40)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(TherapyPalette.canvas, in: RoundedRectangle(cornerRadius: 32))
    }

    @ViewBuilder
    private var actions: some View {
        if confirmingEnd {
            VStack(spacing: 14) {
                Text("session.endConfirmMessage")
                    .typography(.body)
                HStack(spacing: 16) {
                    TherapyButton(title: "session.endCancel", secondary: true, pill: true) {
                        confirmingEnd = false
                    }
                    TherapyButton(title: "session.endConfirm", pill: true, brand: true, action: onEnd)
                }
            }
        } else {
            HStack(spacing: 16) {
                TherapyButton(title: "session.endSession", secondary: true, pill: true) {
                    confirmingEnd = true
                }
                TherapyButton(
                    title: "session.resumeExercise",
                    symbol: "play.fill",
                    disabled: resumeDisabled,
                    pill: true,
                    brand: true,
                    action: onResume
                )
            }
        }
    }

    private static func clock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

// MARK: - Set summary

/// One set in the results panel.
struct TherapySetResult: Identifiable, Equatable {
    enum State: Equatable {
        case done
        case current
        case upcoming
    }

    let number: Int
    let done: Int
    let goal: Int
    let state: State

    var id: Int {
        number
    }
}

/// "Set 2 selesai!" between sets, or "Latihan selesai" after the last one: a rust check,
/// a short message, the result of every set and the total.
struct TherapySetSummary<Actions: View>: View {
    let heading: TherapyExerciseHeading
    let headline: Text
    let message: Text
    let results: [TherapySetResult]
    let total: Text
    /// Optional line under the panel, such as the rest countdown.
    var footer: Text? = nil
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                heading

                TherapyCompletionMark(size: 124, tint: TherapyPalette.brand)
                    .padding(.top, 12)

                VStack(spacing: 10) {
                    headline
                        .typography(size: 40, weight: .bold, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                    message
                        .typography(size: 24, weight: .regular, relativeTo: .title3)
                }
                .multilineTextAlignment(.center)

                panel

                if let footer {
                    footer
                        .typography(size: 22, weight: .regular, relativeTo: .title3)
                        .foregroundStyle(TherapyPalette.muted)
                        .monospacedDigit()
                }

                actions
            }
            .foregroundStyle(TherapyPalette.ink)
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
    }

    private var panel: some View {
        VStack(spacing: 20) {
            HStack(spacing: 0) {
                ForEach(results) { result in
                    if result.number != results.first?.number {
                        Rectangle()
                            .fill(TherapyPalette.outline)
                            .frame(width: 1.5, height: 80)
                    }
                    setColumn(result)
                        .frame(maxWidth: .infinity)
                }
            }

            total
                .typography(size: 24, weight: .regular, relativeTo: .title3)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: 820)
        .background(TherapyPalette.planPanel, in: RoundedRectangle(cornerRadius: 28))
    }

    private func setColumn(_ result: TherapySetResult) -> some View {
        let finished = result.state == .done
        let tint = finished ? TherapyPalette.brand : TherapyPalette.muted

        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: finished ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(tint)
                Text("session.setNumber \(result.number)")
                    .foregroundStyle(finished ? TherapyPalette.ink : TherapyPalette.muted)
            }
            .typography(size: 24, weight: .medium, relativeTo: .title3)

            Text(verbatim: "\(result.done) / \(result.goal)")
                .typography(size: 36, weight: .bold, relativeTo: .title)
                .foregroundStyle(tint)

            Text("session.repetitionsLower")
                .typography(size: 20, weight: .regular, relativeTo: .callout)
                .foregroundStyle(TherapyPalette.muted)
        }
        .accessibilityElement(children: .combine)
    }
}
