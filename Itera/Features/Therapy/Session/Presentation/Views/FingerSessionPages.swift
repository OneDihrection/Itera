//
//  FingerSessionPages.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

// These pages cover the session while a set ends and during rest. They are overlays,
// so the camera preview underneath stays mounted for the whole session, as the system
// design requires. Each page keeps a pause action, so pause and stop remain reachable by
// touch at every stage.

// MARK: - Set summary

/// After each set, and through the rest that follows: what was done and what comes next.
/// The last set of a movement shows the all-done wording.
struct TMFingerSetSummaryPage: View {
    let model: FingerSessionViewModel

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TMTherapySetSummary(
            heading: TMTherapyExerciseHeading(
                eyebrow: dependencies.dailyPlan.currentNumber.map { Text("plan.exerciseNumber \($0)") },
                title: Text(verbatim: model.exerciseTitle)
            ),
            headline: allSetsDone
                ? Text("session.allDoneTitle")
                : Text("session.setDone \(model.activity.completedSets)"),
            message: message,
            results: results,
            total: allSetsDone
                ? Text("session.total \(repetitionsDone)")
                : Text("session.totalOf \(repetitionsDone) \(model.routine.repetitions * model.routine.sets)"),
            footer: restLine
        ) {
            actions
        }
    }

    private var allSetsDone: Bool {
        model.activity.completedSets >= model.routine.sets
    }

    /// Another movement of the finger program follows this one.
    private var moreMovements: Bool {
        model.engine.summary.exerciseIndex < model.routine.exercises.count - 1
    }

    /// Finger sets end only when the goal is reached, so every finished set is goal/goal.
    private var results: [TherapySetResult] {
        (1...max(1, model.routine.sets)).map { number in
            let finished = number <= model.activity.completedSets

            return TherapySetResult(
                number: number,
                done: finished ? model.routine.repetitions : 0,
                goal: model.routine.repetitions,
                state: finished ? .done : .upcoming
            )
        }
    }

    private var repetitionsDone: Int {
        model.activity.completedSets * model.routine.repetitions
    }

    private var message: Text {
        guard allSetsDone else {
            return Text("session.setRest \(model.activity.completedSets + 1)")
        }

        return moreMovements ? Text("session.nextMovementRest") : Text("session.allDoneMessage")
    }

    private var restLine: Text? {
        guard model.activity.phase == .rest else {
            return nil
        }

        let seconds = Int(model.activity.remaining.rounded(.up))

        guard !allSetsDone else {
            return Text("session.nextMovementIn \(seconds)")
        }

        return Text("session.nextSetIn \(model.activity.completedSets + 1) \(seconds)")
    }

    /// Pause stays reachable by touch; during the rest the caregiver may also skip it.
    private var actions: some View {
        HStack(spacing: 16) {
            TMTherapyButton(title: "session.pauseAction", symbol: "pause.fill", pill: true, brand: true) {
                model.handleCommand(.pause)
            }

            if model.activity.phase == .rest {
                TMTherapyButton(title: "rest.skip", symbol: "forward.fill", secondary: true, pill: true, action: model.skipRest)
            }
        }
        .frame(maxWidth: 640)
    }
}

// MARK: - Next up

/// Shown at the end of a rest, with the next movement's demonstration playing.
struct TMFingerUpcomingPage: View {
    let model: FingerSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            TMFingerSessionCloseHeader(model: model, title: nil)

            Spacer(minLength: 16)

            if let upcoming = model.upcoming {
                VStack(spacing: 44) {
                    TMTherapyMediaPanel(padding: 14) {
                        TMFingerExampleView(
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
struct TMFingerSessionCloseHeader: View {
    let model: FingerSessionViewModel
    let title: LocalizedStringKey?
    var trailingContentWidth: CGFloat = 0

    var body: some View {
        TMTherapyPageHeader(
            title: title ?? "",
            leadingTitle: "session.close",
            leadingSymbol: "xmark",
            leadingAction: { model.handleCommand(.pause) },
            trailingContentWidth: trailingContentWidth
        )
    }
}
