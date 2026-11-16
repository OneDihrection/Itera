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
    var audio: SessionAudioService { get }
    var permissions: PermissionManager { get }
    /// Readiness waits for interrupted-session recovery before therapy can start.
    var historyRecovery: any HistoryRecovering { get }
    var homeRouter: HomeRouter { get }
    /// Shared with `DailyPlanViewModel`, which drives the plan's navigation.
    var planRouter: PlanRouter { get }
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

/// What the settings sheet can present over itself.
protocol PracticePreferencesContentBuildable {
    #if DEBUG
    associatedtype DebugPlanEditorScreen: View

    @ViewBuilder @MainActor func buildDebugPlanEditor() -> DebugPlanEditorScreen
    #endif
}

@MainActor
final class HomeBuilder: HomeContentBuildable, PracticePreferencesContentBuildable {
    private let dependency: any HomeDependency

    /// Created once: it wires the router's hooks to its stack, sheet and cover, so a rebuilt
    /// root must not replace it.
    private lazy var homeViewModel = HomeScreenViewModel(
        fingers: dependency.fingers,
        armRoutine: dependency.armRoutine,
        taskRoutine: dependency.taskRoutine,
        plan: dependency.dailyPlan,
        homeRouter: dependency.homeRouter,
        planRouter: dependency.planRouter
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
            audio: dependency.audio,
            readiness: TherapyReadinessViewModel(
                permissions: dependency.permissions,
                audio: dependency.audio,
                history: dependency.historyRecovery
            ),
            narration: DailyPlanIntroNarration()
        )

        TMDailyPlanIntroView(viewModel: viewModel)
    }

    @ViewBuilder func buildPracticePreferences() -> some View {
        let viewModel: some PracticePreferencesViewModelProtocol = PracticePreferencesViewModel(
            home: dependency.fingers,
            plan: dependency.dailyPlan,
            router: dependency.homeRouter
        )

        TMPracticePreferencesView(viewModel: viewModel, builder: self)
    }

    #if DEBUG
    @ViewBuilder func buildDebugPlanEditor() -> some View {
        let viewModel: some DebugPlanEditorViewModelProtocol = DebugPlanEditorViewModel(
            plan: dependency.dailyPlan
        )

        TMDebugPlanEditorView(viewModel: viewModel)
    }
    #endif

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
                audio: dependency.audio
            )

            TMDailyPlanNextView(viewModel: viewModel, builder: self)
        }
    }
}
