//
//  AppRouterView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

@MainActor
enum AppRouterView {
    /// Builds a route's page through the factory, which injects only what that page uses.
    @ViewBuilder
    static func destination(_ route: AppRoute, dependencies: AppDependencies) -> some View {
        switch route {
        case .balanceSession(let exercise, let settings):
            dependencies.makeBalanceSessionView(exercise: exercise, settings: settings)
                .environment(\.locale, AppLanguage.selected.locale)
        case .therapySession(let routine):
            dependencies.makeTherapySessionView(routine: routine)
                .environment(\.buttonFeedback, {})
                .environment(\.locale, AppLanguage.selected.locale)
        case .sessionReport(let id):
            dependencies.makeSessionReportView(id: id)
                .environment(\.locale, AppLanguage.selected.locale)
        case .reports:
            dependencies.makeFingerReportsView()
        case .report(let id):
            dependencies.makeFingerReportDetailView(id: id)
        case .fingerSession:
            dependencies.makeFingerSessionView()
        case .sessionComplete:
            dependencies.makeFingerSessionCompleteView()
        case .practicePreferences:
            dependencies.makePracticePreferencesView()
        case .planNext:
            dependencies.makeDailyPlanNextView()
        case .planIntro(let itemID):
            dependencies.makeDailyPlanIntroView(itemID: itemID)
        #if DEBUG
        case .debugPlanEditor:
            dependencies.makeDebugPlanEditorView()
        #endif
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
        dependencies.makeHomeView()
            .typography(.body)
            .withAppRouter(dependencies: dependencies)
            .environment(router)
    }
}

#Preview("Root") {
    TMRouterPreview()
}

#Preview("Pushed route") {
    TMRouterPreview(route: .practicePreferences)
}

#Preview("Sheet") {
    TMRouterPreview(route: .practicePreferences, sheet: true)
}
#endif
