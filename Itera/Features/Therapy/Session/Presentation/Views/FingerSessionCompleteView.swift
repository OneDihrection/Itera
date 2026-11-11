//
//  FingerSessionCompleteView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

/// The shared all-done page for the finger exercises: saves the finished session, then offers a
/// way on to the next exercise or to progress.
struct TMFingerSessionCompleteView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var savingFinished = false

    private var summary: FingerSessionSummary? {
        dependencies.session?.finalSummary
    }

    var body: some View {
        TMTherapySetSummary(
            heading: TMTherapyExerciseHeading(
                eyebrow: dependencies.dailyPlan.currentNumber.map { Text("plan.exerciseNumber \($0)") },
                title: Text(verbatim: dependencies.session?.exerciseTitle ?? "")
            ),
            headline: Text(completed ? "session.allDoneTitle" : "done.titlePartial"),
            message: Text(completed ? "session.allDoneMessage" : "done.messagePartial"),
            results: results,
            total: Text("session.total \(summary?.totalRepetitions ?? 0)")
        ) {
            closingAction
        }
        .environment(\.colorScheme, .light)
        .environment(\.locale, dependencies.session?.sessionLanguage.locale ?? AppLanguage.selected.locale)
        .interactiveDismissDisabled()
        .task { await saveSummary() }
        .task(id: savingFinished && scenePhase == .active && automaticallyRests) {
            guard savingFinished, scenePhase == .active, automaticallyRests else {
                return
            }

            try? await Task.sleep(for: DailyPlanViewModel.completionPreviewDuration)

            guard !Task.isCancelled, scenePhase == .active, automaticallyRests else {
                return
            }

            close()
        }
    }

    /// The way on appears once saving has finished, whether or not it succeeded, so the
    /// patient is never stuck on this page.
    @ViewBuilder
    private var closingAction: some View {
        if automaticallyRests {
            if !savingFinished {
                ProgressView("session.saving")
            }
        } else {
            TMTherapyFinishActions(
                title: closingTitle,
                symbol: dependencies.dailyPlan.isRunning ? "play.fill" : nil,
                disabled: !savingFinished,
                action: close
            ) {
                if !savingFinished {
                    ProgressView()
                }
            }
        }
    }

    private var automaticallyRests: Bool {
        completed && dependencies.dailyPlan.hasAutomaticRest
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

    private func saveSummary() async {
        await dependencies.session?.saveFinalSummary()
        if dependencies.session?.finalSummarySaved == true {
            await dependencies.home.refresh()
        }
        savingFinished = true
    }

    private var completed: Bool {
        summary?.outcome == .completed
    }

    /// While today's plan runs, this page leads on to the next exercise instead of Progress.
    private var closingTitle: LocalizedStringKey {
        dependencies.dailyPlan.isRunning ? "plan.nextContinue" : "done.viewProgress"
    }

    private func close() {
        guard !dependencies.dailyPlan.isRunning else {
            dependencies.dailyPlan.finish(completed: completed, router: router)
            return
        }

        router.dismissFullScreenCover()
        router.push(.reports)
    }
}
