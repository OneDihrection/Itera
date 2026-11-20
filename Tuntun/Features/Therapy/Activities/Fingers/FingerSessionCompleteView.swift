//
//  FingerSessionCompleteView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

/// The shared all-done page for the finger exercises: saves the finished session, then offers a
/// way on to the next exercise or to progress.
struct TMFingerSessionCompleteView<ViewModel: FingerSessionCompleteViewModelProtocol>: View {
    @State private var viewModel: ViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var summary: FingerSessionSummary? {
        viewModel.summary
    }

    private var savingFinished: Bool {
        viewModel.savingFinished
    }

    private var completed: Bool {
        viewModel.completed
    }

    private var automaticallyRests: Bool {
        viewModel.automaticallyRests
    }

    var body: some View {
        TMTherapySetSummary(
            heading: TMTherapyExerciseHeading(
                eyebrow: viewModel.exerciseNumber.map { Text("plan.exerciseNumber \($0)") },
                title: Text(verbatim: viewModel.exerciseTitle)
            ),
            headline: Text(completed ? "session.allDoneTitle" : "done.titlePartial"),
            message: Text(completed ? "session.allDoneMessage" : "done.messagePartial"),
            results: results,
            total: Text("session.total \(summary?.totalRepetitions ?? 0)")
        ) {
            closingAction
        }
        .overlay {
            if !savingFinished {
                TMLoadingOverlay(message: "loading.finishingSession")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: savingFinished)
        .environment(\.colorScheme, .light)
        .environment(\.locale, viewModel.sessionLocale)
        .interactiveDismissDisabled()
        .task { await viewModel.save() }
        .task(id: savingFinished && scenePhase == .active && automaticallyRests) {
            guard savingFinished, scenePhase == .active, automaticallyRests else {
                return
            }

            try? await Task.sleep(for: DailyPlanTiming.completionPreview)

            guard !Task.isCancelled, scenePhase == .active, automaticallyRests else {
                return
            }

            viewModel.close()
        }
    }

    /// The way on appears once saving has finished, whether or not it succeeded, so the
    /// patient is never stuck on this page. The loading overlay covers the page while it saves.
    @ViewBuilder
    private var closingAction: some View {
        if !automaticallyRests {
            TMTherapyFinishActions(
                title: closingTitle,
                symbol: viewModel.isPlanRunning ? "play.fill" : nil,
                disabled: !savingFinished,
                action: viewModel.close
            ) {
                EmptyView()
            }
        }
    }

    /// Every set of every movement. Finger sets end only when the goal is reached, so a finished
    /// set is goal/goal and the rest are still to do.
    private var results: [TherapySetResult] {
        guard let summary else {
            return []
        }

        let sets = max(1, summary.routine.sets)
        let goal = summary.routine.repetitions

        return summary.results
            .enumerated()
            .flatMap { movement, result in
                (1...sets).map { number in
                    let finished = number <= result.completedSets

                    return TherapySetResult(
                        number: movement * sets + number,
                        done: finished ? goal : 0,
                        goal: goal,
                        state: finished ? .done : .upcoming
                    )
                }
            }
    }

    /// While today's plan runs, this page leads on to the next exercise instead of Progress.
    private var closingTitle: LocalizedStringKey {
        viewModel.isPlanRunning ? "plan.nextContinue" : "done.viewProgress"
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockFingerSessionCompleteViewModel: FingerSessionCompleteViewModelProtocol {
    let summary: FingerSessionSummary? = FingerSessionSummary(
        id: UUID(),
        started: .now,
        ended: .now,
        routine: FingerRoutine(),
        results: [],
        outcome: .completed,
        feeling: nil,
        exerciseIndex: 0
    )
    let exerciseTitle = "Sentuh Jempol ke Jari"
    let sessionLocale = AppLanguage.selected.locale
    let exerciseNumber: Int? = 1
    let isPlanRunning = true
    let completed = true
    let automaticallyRests = false
    let savingFinished = true

    func save() async {}
    func close() {}
}

#Preview("Finger complete") {
    TMFingerSessionCompleteView(viewModel: MockFingerSessionCompleteViewModel())
}
#endif
