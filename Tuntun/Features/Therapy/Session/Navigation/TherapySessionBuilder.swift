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
    var trackingService: BodyTrackingService { get }
    var audioService: SessionAudioService { get }
    var sessions: any SessionRepository { get }
    var permissionService: PermissionService { get }
    var fingers: FingerHomeViewModel { get }
    var fingerSessionService: FingerSessionService { get }
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
            trackingService: dependency.trackingService,
            audioService: dependency.audioService,
            repository: dependency.sessions,
            routine: routine
        )

        TMTherapySessionView(
            model: model,
            plan: dependency.planReporting,
            permissionService: dependency.permissionService,
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
            trackingService: dependency.trackingService,
            audioService: dependency.audioService,
            repository: dependency.sessions,
            settings: settings,
            exercise: exercise
        )

        TMBalanceSessionView(
            model: model,
            plan: dependency.planReporting,
            permissionService: dependency.permissionService,
            router: dependency.sessionRouter
        )
        .environment(\.locale, AppLanguage.selected.locale)
    }

    @ViewBuilder func buildFingerSession() -> some View {
        TMFingerSessionView(
            fingerSessionService: dependency.fingerSessionService,
            plan: dependency.planReporting,
            router: dependency.sessionRouter
        )
    }

    @ViewBuilder func buildFingerSessionComplete() -> some View {
        let viewModel: some FingerSessionCompleteViewModelProtocol = FingerSessionCompleteViewModel(
            fingerSessionService: dependency.fingerSessionService,
            plan: dependency.planReporting,
            home: dependency.fingers,
            tabs: dependency.tabRouter,
            router: dependency.sessionRouter
        )

        TMFingerSessionCompleteView(viewModel: viewModel)
    }
}

