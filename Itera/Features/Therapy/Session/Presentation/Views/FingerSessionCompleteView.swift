//
//  FingerSessionCompleteView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

/// Saves the finished session and automatically routes to its next destination.
struct TMFingerSessionCompleteView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var savingFinished = false

    private var summary: FingerSessionSummary? {
        dependencies.session?.finalSummary
    }

    var body: some View {
        Group {
            if automaticallyRests, let summary, let exercise = summary.results.last {
                setSummary(summary, exercise: exercise)
            } else {
                ProgressView("session.saving")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TherapyPalette.canvas)
            }
        }
        .environment(\.locale, dependencies.session?.sessionLanguage.locale ?? AppLanguage.selected.locale)
        .interactiveDismissDisabled()
        .task { await saveSummary() }
        .task(id: savingFinished && scenePhase == .active) {
            guard savingFinished, scenePhase == .active else {
                return
            }

            if automaticallyRests {
                try? await Task.sleep(for: DailyPlanViewModel.completionPreviewDuration)
            }

            guard !Task.isCancelled, scenePhase == .active else {
                return
            }
            close()
        }
    }

    private var automaticallyRests: Bool {
        completed && dependencies.dailyPlan.hasAutomaticRest
    }

    private func setSummary(_ summary: FingerSessionSummary, exercise: FingerExerciseResult) -> some View {
        let goal = summary.routine.repetitions
        let results = (0..<exercise.completedSets).map { index in
            TherapySetResult(number: index + 1, done: goal, goal: goal, state: .done)
        }

        return TMTherapySetSummary(
            heading: TMTherapyExerciseHeading(
                eyebrow: dependencies.dailyPlan.currentNumber.map { Text("plan.exerciseNumber \($0)") },
                title: Text(LocalizedStringKey(exercise.kind.title))
            ),
            headline: Text("session.allDoneTitle"),
            message: Text("session.allDoneMessage"),
            results: results,
            total: Text("session.total \(summary.totalRepetitions)")
        ) {
            if !savingFinished {
                ProgressView()
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

    private func close() {
        guard !dependencies.dailyPlan.isRunning else {
            dependencies.dailyPlan.finish(completed: completed, router: router)
            return
        }

        router.dismissFullScreenCover()
        router.push(.reports)
    }
}
