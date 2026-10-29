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
            FingerHomeView()
        case .plan:
            FingerPlanView()
        case .reports:
            FingerReportsView()
        case .achievements:
            PracticeAchievementsView()
        case .achievementCelebration:
            AchievementCelebrationView()
        case .achievement(let id):
            PracticeAchievementDetailView(id: id)
        case .report(let id):
            FingerReportDetailView(id: id)
        case .fingerSession:
            FingerSessionView()
        case .reflection:
            FingerReflectionView()
        case .routineSettings:
            FingerRoutineSettingsView()
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
