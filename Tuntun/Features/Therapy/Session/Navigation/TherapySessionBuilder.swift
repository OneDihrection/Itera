//
//  TherapySessionBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// What the guided, Balancing and finger session pages need from their parent.
@MainActor
protocol TherapySessionDependency {
    var tracking: BodyTrackingService { get }
    var audio: SessionAudioService { get }
    var sessions: any SessionRepository { get }
    var permissions: PermissionManager { get }
    var fingers: FingerHomeViewModel { get }
    var fingerSessions: FingerSessionLauncher { get }
    /// Sessions report their finishing action to today's plan.
    var planReporting: any DailyPlanSessionReporting { get }
    var sessionRouter: any SessionRouterProtocol { get }
    var tabRouter: any TabRouterProtocol { get }
}

@MainActor
final class TherapySessionBuilder {
    private let dependency: any TherapySessionDependency

    init(dependency: any TherapySessionDependency) {
        self.dependency = dependency
    }

    @ViewBuilder func buildTherapySession(routine: Routine) -> some View {
        let model: some TherapySessionViewModelProtocol = TherapySessionViewModel(
            tracking: dependency.tracking,
            audio: dependency.audio,
            repository: dependency.sessions,
            routine: routine
        )

        TMTherapySessionView(
            model: model,
            plan: dependency.planReporting,
            permissions: dependency.permissions,
            router: dependency.sessionRouter
        )
        .environment(\.buttonFeedback, {})
        .environment(\.locale, AppLanguage.selected.locale)
    }

    @ViewBuilder func buildBalanceSession(
        exercise: BalanceExercise,
        settings: BalancePracticeSettings
    ) -> some View {
        let model: some BalanceSessionViewModelProtocol = BalanceSessionViewModel(
            tracking: dependency.tracking,
            audio: dependency.audio,
            repository: dependency.sessions,
            settings: settings,
            exercise: exercise
        )

        TMBalanceSessionView(
            model: model,
            plan: dependency.planReporting,
            permissions: dependency.permissions,
            router: dependency.sessionRouter
        )
        .environment(\.locale, AppLanguage.selected.locale)
    }

    @ViewBuilder func buildFingerSession() -> some View {
        TMFingerSessionView(
            launcher: dependency.fingerSessions,
            plan: dependency.planReporting,
            router: dependency.sessionRouter
        )
    }

    @ViewBuilder func buildFingerSessionComplete() -> some View {
        let viewModel: some FingerSessionCompleteViewModelProtocol = FingerSessionCompleteViewModel(
            launcher: dependency.fingerSessions,
            plan: dependency.planReporting,
            home: dependency.fingers,
            tabs: dependency.tabRouter,
            router: dependency.sessionRouter
        )

        TMFingerSessionCompleteView(viewModel: viewModel)
    }
}

