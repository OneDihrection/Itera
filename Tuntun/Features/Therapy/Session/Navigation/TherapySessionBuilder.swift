//
//  TherapySessionBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

#if DEBUG
/// Debug-only: the session screen filled from a fixed snapshot.
protocol TherapySessionFixtureBuildable {
    associatedtype FixtureScreen: View

    @ViewBuilder @MainActor func buildTherapySession(fixture: SessionSnapshot) -> FixtureScreen
}
#endif

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
        let model: some TherapySessionViewModelProtocol = TherapySessionViewModel(
            tracking: component.tracking,
            audio: component.audio,
            repository: component.sessions,
            routine: routine
        )

        TMTherapySessionView(
            model: model,
            plan: component.planReporting,
            permissions: component.permissions,
            router: component.sessionRouter
        )
        .environment(\.buttonFeedback, {})
        .environment(\.locale, AppLanguage.selected.locale)
    }

    #if DEBUG
    /// Debug fixtures render a fixed snapshot without capture or audio.
    @ViewBuilder func buildTherapySession(fixture: SessionSnapshot) -> some View {
        let model: some TherapySessionViewModelProtocol = TherapySessionViewModel.presentationFixture(fixture)

        TMTherapySessionView(
            model: model,
            plan: component.planReporting,
            permissions: component.permissions,
            router: component.sessionRouter,
            presentationOnly: true
        )
    }
    #endif

    @ViewBuilder func buildBalanceSession(
        exercise: BalanceExercise,
        settings: BalancePracticeSettings
    ) -> some View {
        let model: some BalanceSessionViewModelProtocol = BalanceSessionViewModel(
            tracking: component.tracking,
            audio: component.audio,
            repository: component.sessions,
            settings: settings,
            exercise: exercise
        )

        TMBalanceSessionView(
            model: model,
            plan: component.planReporting,
            permissions: component.permissions,
            router: component.sessionRouter
        )
        .environment(\.locale, AppLanguage.selected.locale)
    }

    @ViewBuilder func buildFingerSession() -> some View {
        TMFingerSessionView(
            launcher: component.fingerSessions,
            plan: component.planReporting,
            router: component.sessionRouter
        )
    }

    @ViewBuilder func buildFingerSessionComplete() -> some View {
        let viewModel: some FingerSessionCompleteViewModelProtocol = FingerSessionCompleteViewModel(
            launcher: component.fingerSessions,
            plan: component.planReporting,
            home: component.fingers,
            tabs: component.tabRouter,
            router: component.sessionRouter
        )

        TMFingerSessionCompleteView(viewModel: viewModel)
    }
}

#if DEBUG
extension TherapySessionBuilder: TherapySessionFixtureBuildable {}
#endif
