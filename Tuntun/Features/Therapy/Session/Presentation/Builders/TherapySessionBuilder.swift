//
//  TherapySessionBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// Builds the session pages today's plan runs in its full-screen cover.
protocol TherapySessionBuildable {
    associatedtype TherapySessionScreen: View
    associatedtype BalanceSessionScreen: View
    associatedtype FingerSessionScreen: View
    associatedtype FingerSessionCompleteScreen: View

    @ViewBuilder @MainActor func buildTherapySession(routine: Routine) -> TherapySessionScreen
    @ViewBuilder @MainActor func buildBalanceSession(
        exercise: BalanceExercise,
        settings: BalancePracticeSettings
    ) -> BalanceSessionScreen
    @ViewBuilder @MainActor func buildFingerSession() -> FingerSessionScreen
    @ViewBuilder @MainActor func buildFingerSessionComplete() -> FingerSessionCompleteScreen
}

@MainActor
final class TherapySessionBuilder: TherapySessionBuildable {
    private let component: TherapySessionComponent

    init(component: TherapySessionComponent) {
        self.component = component
    }

    @ViewBuilder func buildTherapySession(routine: Routine) -> some View {
        let model = TherapySessionViewModel(
            tracking: component.tracking,
            audio: component.audio,
            repository: component.sessions,
            routine: routine
        )

        TMTherapySessionView(
            model: model,
            plan: component.dailyPlan,
            permissions: component.permissions,
            router: component.sessionRouter
        )
        .environment(\.buttonFeedback, {})
        .environment(\.locale, AppLanguage.selected.locale)
    }

    #if DEBUG
    @ViewBuilder func buildTherapySession(fixture: SessionSnapshot) -> some View {
        TMTherapySessionView(
            fixture: fixture,
            plan: component.dailyPlan,
            permissions: component.permissions,
            router: component.sessionRouter
        )
    }
    #endif

    @ViewBuilder func buildBalanceSession(
        exercise: BalanceExercise,
        settings: BalancePracticeSettings
    ) -> some View {
        let model = BalanceSessionViewModel(
            tracking: component.tracking,
            audio: component.audio,
            repository: component.sessions,
            settings: settings,
            exercise: exercise
        )

        TMBalanceSessionView(
            model: model,
            plan: component.dailyPlan,
            permissions: component.permissions,
            router: component.sessionRouter
        )
        .environment(\.locale, AppLanguage.selected.locale)
    }

    @ViewBuilder func buildFingerSession() -> some View {
        TMFingerSessionView(
            launcher: component.fingerSessions,
            plan: component.dailyPlan,
            router: component.sessionRouter
        )
    }

    @ViewBuilder func buildFingerSessionComplete() -> some View {
        TMFingerSessionCompleteView(
            launcher: component.fingerSessions,
            plan: component.dailyPlan,
            home: component.fingers,
            tabs: component.tabRouter,
            router: component.sessionRouter
        )
    }
}
