//
//  AppRouterView.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

@MainActor
enum AppRouterView {
    @ViewBuilder
    static func destination(_ route: AppRoute) -> some View {
        switch route {
        case .home:
            HomeView()
        case .fingerHome(let category):
            FingerHomeView(category: category)
        case .therapyOverview(let category):
            TherapyOverview(category: category)
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .armRotationHome:
            ArmRotationHomeView()
                .environment(\.locale, AppLanguage.selected.locale)
        case .balanceOverview(let exercise):
            BalanceOverviewView(exercise: exercise)
                .environment(\.locale, AppLanguage.selected.locale)
        case .balanceSession(let exercise, let repetitions, let holdSeconds, let armSelection):
            BalanceSessionDestination(
                exercise: exercise,
                repetitions: repetitions,
                holdSeconds: holdSeconds,
                armSelection: armSelection
            )
                .environment(\.locale, AppLanguage.selected.locale)
        case .routineConfiguration(let category):
            RoutineConfigurationView(category: category)
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .exercisePicker(let category):
            RoutineExercisePicker(category: category)
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .therapySession:
            SessionDestination()
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .plan(let category):
            FingerPlanView(category: category)
        case .taskReports:
            TaskReportsDestination()
                .environment(\.locale, AppLanguage.selected.locale)
        case .reports:
            FingerReportsView()
        case .achievements:
            PracticeAchievementsView()
        case .achievementCelebration:
            AchievementCelebrationView()
        case .achievement(let id):
            PracticeAchievementDetailView(id: id)
        case .achievementShare(let id):
            AchievementShareDestination(id: id)
        case .report(let id):
            FingerReportDetailView(id: id)
        case .fingerPause:
            FingerPauseView()
        case .fingerSession:
            FingerSessionView()
        case .reflection:
            FingerReflectionView()
        case .practicePreferences:
            PracticePreferencesView()
        case .routineSettings(let category):
            FingerRoutineSettingsView(category: category)
        case .exercisePreview(let exercise):
            FingerExercisePreviewView(exercise: exercise)
        }
    }
}

#if DEBUG
private struct RouterPreview: View {
    @State private var router: NavigationRouter
    @State private var dependencies = AppDependencies(permissions: PermissionManager())

    init(route: AppRoute? = nil, sheet: Bool = false) {
        let router = NavigationRouter()

        if let route {
            if sheet {
                router.presentSheet(route)
            } else {
                router.push(route)
            }
        }

        _router = State(initialValue: router)
    }

    var body: some View {
        ContentView()
            .typography(.body)
            .withAppRouter()
            .environment(router)
            .environment(dependencies)
            .environment(dependencies.permissions)
    }
}

#Preview("Root") {
    RouterPreview()
}

#Preview("Pushed route") {
    RouterPreview(route: .home)
}

#Preview("Sheet") {
    RouterPreview(route: .home, sheet: true)
}
#endif

private struct SessionDestination: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TherapySessionView(model: dependencies.makeSession())
    }
}

private struct BalanceSessionDestination: View {
    @Environment(AppDependencies.self) private var dependencies
    let exercise: BalanceExercise
    let repetitions: Int
    let holdSeconds: Int
    let armSelection: BalanceArmSelection

    var body: some View {
        BalanceSessionView(model: BalanceSessionViewModel(
            tracking: dependencies.tracking,
            audio: dependencies.audio,
            repetitions: repetitions,
            holdSeconds: holdSeconds,
            armSelection: armSelection,
            exercise: exercise
        ))
    }
}

private struct TaskReportsDestination: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TaskReportsView(model: TaskReportsViewModel(repository: dependencies.sessions))
    }
}
