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
            TMHomeView()
        case .fingerHome(let category):
            TMFingerHomeView(category: category)
        case .therapyOverview(let category):
            TMTherapyOverview(category: category)
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .armRotationHome:
            TMArmRotationHomeView()
                .environment(\.locale, AppLanguage.selected.locale)
        case .balanceOverview(let exercise):
            TMBalanceOverviewView(exercise: exercise)
                .environment(\.locale, AppLanguage.selected.locale)
        case .balanceSession(let exercise, let settings):
            TMBalanceSessionDestination(exercise: exercise, settings: settings)
                .environment(\.locale, AppLanguage.selected.locale)
        case .routineConfiguration(let category):
            TMRoutineConfigurationView(category: category)
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .exercisePicker(let category):
            TMRoutineExercisePicker(category: category)
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .therapySession:
            TMSessionDestination()
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .plan(let category):
            TMFingerPlanView(category: category)
        case .taskReports(let category):
            TMTaskReportsDestination(category: category)
                .environment(\.locale, AppLanguage.selected.locale)
        case .sessionReport(let id):
            TMSessionReportDestination(id: id)
                .environment(\.locale, AppLanguage.selected.locale)
        case .reports:
            TMFingerReportsView()
        case .report(let id):
            TMFingerReportDetailView(id: id)
        case .fingerSession:
            TMFingerSessionView()
        case .sessionComplete:
            TMFingerSessionCompleteView()
        case .practicePreferences:
            TMPracticePreferencesView()
        case .routineSettings(let category):
            TMFingerRoutineSettingsView(category: category)
        case .exercisePreview(let exercise):
            TMFingerExercisePreviewView(exercise: exercise)
        case .planNext:
            TMDailyPlanNextView()
        case .planIntro(let itemID):
            TMDailyPlanIntroView(itemID: itemID)
        }
    }
}

#if DEBUG
private struct TMRouterPreview: View {
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
        TMContentView()
            .typography(.body)
            .withAppRouter()
            .environment(router)
            .environment(dependencies)
            .environment(dependencies.permissions)
    }
}

#Preview("Root") {
    TMRouterPreview()
}

#Preview("Pushed route") {
    TMRouterPreview(route: .home)
}

#Preview("Sheet") {
    TMRouterPreview(route: .home, sheet: true)
}
#endif

private struct TMSessionDestination: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TMTherapySessionView(model: dependencies.makeSession())
    }
}

private struct TMBalanceSessionDestination: View {
    @Environment(AppDependencies.self) private var dependencies
    let exercise: BalanceExercise
    let settings: BalancePracticeSettings

    var body: some View {
        TMBalanceSessionView(model: BalanceSessionViewModel(
            tracking: dependencies.tracking,
            audio: dependencies.audio,
            repository: dependencies.sessions,
            settings: settings,
            exercise: exercise
        ))
    }
}

private struct TMTaskReportsDestination: View {
    let category: TherapyCategory
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TMTaskReportsView(model: TaskReportsViewModel(category: category, repository: dependencies.sessions))
    }
}

private struct TMSessionReportDestination: View {
    let id: UUID
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TMSessionReportView(model: SessionReportViewModel(sessionID: id, repository: dependencies.sessions))
    }
}
