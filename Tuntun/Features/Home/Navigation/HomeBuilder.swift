//
//  HomeBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// What Beranda, its settings, today's plan and its intro pages need from their parent.
@MainActor
protocol HomeDependency {
    var fingers: FingerHomeViewModel { get }
    var armRoutine: RoutineViewModel { get }
    var taskRoutine: RoutineViewModel { get }
    var dailyPlan: DailyPlanViewModel { get }
    /// The intro reads its narration and validates readiness before a session opens.
    var audioService: SessionAudioService { get }
    var permissionService: PermissionService { get }
    /// Readiness waits for interrupted-session recovery before therapy can start.
    var historyRecoveryService: any HistoryRecoveryServiceProtocol { get }
    /// Shared with `DailyPlanViewModel`, which drives the plan's navigation, and with the sessions.
    var homeRouter: HomeRouter { get }
    /// Builds the session pages the plan's cover shows; no session UI is written in Home.
    var sessionBuilder: TherapySessionBuilder { get }
}

/// The pages the plan's full-screen cover shows.
protocol PlanCoverBuildable {
    associatedtype CoverPage: View

    @ViewBuilder @MainActor func buildCoverPage(_ route: PlanCoverRoute) -> CoverPage
}

/// The intro the next-exercise page embeds after its rest.
protocol DailyPlanNextContentBuildable {
    associatedtype DailyPlanIntroScreen: View

    /// - Parameters:
    ///   - countdownSeconds: shown in place of Start when the plan opens this intro after a rest.
    ///   - automatic: the intro was opened by the plan, so its reading leads into the session.
    @ViewBuilder @MainActor func buildDailyPlanIntro(
        itemID: String,
        countdownSeconds: Int?,
        automatic: Bool
    ) -> DailyPlanIntroScreen
}

/// What Beranda can push, present as a sheet, or show in its plan cover.
protocol HomeContentBuildable: PlanCoverBuildable, DailyPlanNextContentBuildable {
    associatedtype PracticePreferencesScreen: View

    @ViewBuilder @MainActor func buildPracticePreferences() -> PracticePreferencesScreen
}

@MainActor
final class HomeBuilder: HomeContentBuildable {
    private let dependency: any HomeDependency

    /// Created once, so a rebuilt root keeps the same screen model. The stack, sheet and cover
    /// live in `HomeRouter`.
    private lazy var homeViewModel = HomeScreenViewModel(
        fingers: dependency.fingers,
        armRoutine: dependency.armRoutine,
        taskRoutine: dependency.taskRoutine,
        plan: dependency.dailyPlan,
        router: dependency.homeRouter
    )

    init(dependency: any HomeDependency) {
        self.dependency = dependency
    }

    // MARK: - Root

    @ViewBuilder func buildHome() -> some View {
        let viewModel: some HomeViewModelProtocol = homeViewModel

        TMHomeView(viewModel: viewModel, builder: self)
    }

    // MARK: - Stack and sheets

    @ViewBuilder func buildDailyPlanIntro(
        itemID: String,
        countdownSeconds: Int?,
        automatic: Bool
    ) -> some View {
        let viewModel: some DailyPlanIntroViewModelProtocol = DailyPlanIntroViewModel(
            itemID: itemID,
            countdownSeconds: countdownSeconds,
            automatic: automatic,
            plan: dependency.dailyPlan,
            audioService: dependency.audioService,
            readiness: TherapyReadinessViewModel(
                permissionService: dependency.permissionService,
                audioService: dependency.audioService,
                historyRecoveryService: dependency.historyRecoveryService
            ),
            narration: DailyPlanIntroNarration()
        )

        TMDailyPlanIntroView(viewModel: viewModel)
    }

    @ViewBuilder func buildPracticePreferences() -> some View {
        let viewModel: some PracticePreferencesViewModelProtocol = PracticePreferencesViewModel(
            plan: dependency.dailyPlan,
            router: dependency.homeRouter,
            permissionService: dependency.permissionService
        )

        TMPracticePreferencesView(viewModel: viewModel)
    }

    // MARK: - Plan cover

    @ViewBuilder func buildCoverPage(_ route: PlanCoverRoute) -> some View {
        switch route {
        case .therapySession(let routine):
            dependency.sessionBuilder.buildTherapySession(routine: routine)
        case .balanceSession(let exercise, let settings):
            dependency.sessionBuilder.buildBalanceSession(exercise: exercise, settings: settings)
        case .fingerSession:
            dependency.sessionBuilder.buildFingerSession()
        case .fingerSessionComplete:
            dependency.sessionBuilder.buildFingerSessionComplete()
        case .planNext:
            let viewModel: some DailyPlanNextViewModelProtocol = DailyPlanNextViewModel(
                plan: dependency.dailyPlan,
                audioService: dependency.audioService
            )

            TMDailyPlanNextView(viewModel: viewModel, builder: self)
        }
    }
}
