//
//  FingerSessionPages.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

// These pages cover the session while a set ends and during rest. They are overlays,
// so the camera preview underneath stays mounted for the whole session, as the system
// design requires. Each page keeps a close action that pauses, so pause and stop remain
// reachable by touch at every stage.

// MARK: - Set complete

struct FingerSetCompletePage: View {
    let model: FingerSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            FingerSessionCloseHeader(model: model, title: LocalizedStringKey(model.activity.kind.title))

            Spacer(minLength: 24)

            VStack(spacing: 16) {
                TherapyCompletionMark()
                Text("session.setDone \(model.activity.set)")
                    .typography(size: 44, weight: .bold, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("session.setDoneDetail \(model.activity.repetitions) \(model.routine.repetitions)")
                    .typography(size: 26, weight: .regular, relativeTo: .title3)
            }
            .multilineTextAlignment(.center)

            setList
                .frame(maxWidth: 380)
                .padding(.top, 44)

            Spacer(minLength: 24)
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
    }

    private var setList: some View {
        VStack(spacing: 16) {
            ForEach(1...max(1, model.routine.sets), id: \.self) { number in
                TherapySetRow(
                    title: "session.setNumber \(number)",
                    detail: detail(for: number),
                    state: state(for: number)
                )
            }
        }
    }

    private func state(for number: Int) -> TherapySetRow.State {
        if number <= model.activity.completedSets {
            return .done
        }

        return number == model.activity.completedSets + 1 ? .next : .upcoming
    }

    private func detail(for number: Int) -> LocalizedStringKey? {
        switch state(for: number) {
        case .done:
            return "session.setRepetitions \(model.routine.repetitions) \(model.routine.repetitions)"
        case .next:
            return "session.nextUp"
        case .upcoming:
            return nil
        }
    }
}

// MARK: - Rest

struct FingerRestPage: View {
    let model: FingerSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            FingerSessionCloseHeader(model: model, title: nil)

            Spacer(minLength: 16)

            VStack(spacing: 52) {
                Text("rest.title")
                    .typography(size: 44, weight: .bold, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                TherapyRestCountdown(
                    remaining: model.activity.remaining,
                    total: Double(model.routine.restSeconds),
                    unit: "rest.seconds"
                )
                TherapyButton(title: "rest.skip", pill: true, action: model.skipRest)
                    .frame(maxWidth: 360)
            }

            Spacer(minLength: 16)
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
    }
}

// MARK: - Next up

/// Shown at the end of a rest, with the next movement's demonstration playing.
struct FingerUpcomingPage: View {
    let model: FingerSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            FingerSessionCloseHeader(model: model, title: nil)

            Spacer(minLength: 16)

            if let upcoming = model.upcoming {
                VStack(spacing: 44) {
                    TherapyMediaPanel(padding: 14) {
                        FingerDemonstrationView(
                            exercise: upcoming.exercise,
                            phase: .demonstration,
                            returning: false,
                            finger: 0,
                            side: model.routine.side,
                            paused: model.paused
                        )
                        .background(TherapyPalette.mediaBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .accessibilityLabel("session.example")
                    }
                    .frame(width: 360, height: 390)

                    VStack(spacing: 14) {
                        caption(for: upcoming)
                            .typography(size: 34, weight: .medium, relativeTo: .title)
                        Text("rest.startsIn \(secondsLeft)")
                            .typography(size: 26, weight: .regular, relativeTo: .title3)
                            .foregroundStyle(TherapyPalette.muted)
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                }
            }

            Spacer(minLength: 16)
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
    }

    /// Whole seconds until the rest ends and the next set's countdown begins.
    private var secondsLeft: Int {
        max(0, Int(ceil(model.activity.remaining)))
    }

    private func caption(for upcoming: (exercise: FingerExercise, set: Int)) -> Text {
        guard upcoming.exercise == model.activity.kind else {
            let title = String(
                localized: String.LocalizationValue(upcoming.exercise.title),
                bundle: model.sessionLanguage.resourceBundle
            )
            return Text("rest.nextExercise \(title)")
        }

        return Text("rest.nextSet \(upcoming.set)")
    }
}

// MARK: - Shared header

/// The page header used across session pages: a close circle that pauses the session.
struct FingerSessionCloseHeader: View {
    let model: FingerSessionViewModel
    let title: LocalizedStringKey?
    var trailingContentWidth: CGFloat = 0

    var body: some View {
        TherapyPageHeader(
            title: title ?? "",
            leadingTitle: "session.close",
            leadingSymbol: "xmark",
            leadingAction: { model.handleCommand(.pause) },
            trailingContentWidth: trailingContentWidth
        )
    }
}
