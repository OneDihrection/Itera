//
//  HomeBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// Builds the Home tab's root.
protocol HomeBuildable {
    associatedtype HomeScreen: View

    @ViewBuilder @MainActor func buildHome() -> HomeScreen
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
final class HomeBuilder: HomeBuildable, HomeContentBuildable, PracticePreferencesContentBuildable {
    private let component: HomeComponent

    init(component: HomeComponent) {
        self.component = component
    }

    // MARK: - Root

    @ViewBuilder func buildHome() -> some View {
        let viewModel: some HomeViewModelProtocol = component.homeViewModel

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
            plan: component.dailyPlan,
            audio: component.audio,
            readiness: TherapyReadinessViewModel(
                permissions: component.permissions,
                audio: component.audio,
                history: component.historyRecovery
            ),
            narration: DailyPlanIntroNarration()
        )

        TMDailyPlanIntroView(viewModel: viewModel)
    }

    @ViewBuilder func buildPracticePreferences() -> some View {
        let viewModel: some PracticePreferencesViewModelProtocol = PracticePreferencesViewModel(
            home: component.fingers,
            plan: component.dailyPlan,
            router: component.homeRouter
        )

        TMPracticePreferencesView(viewModel: viewModel, builder: self)
    }

    #if DEBUG
    @ViewBuilder func buildDebugPlanEditor() -> some View {
        let viewModel: some DebugPlanEditorViewModelProtocol = DebugPlanEditorViewModel(
            plan: component.dailyPlan
        )

        TMDebugPlanEditorView(viewModel: viewModel)
    }
    #endif

    // MARK: - Plan cover

    @ViewBuilder func buildCoverPage(_ route: PlanCoverRoute) -> some View {
        switch route {
        case .therapySession(let routine):
            component.sessionBuilder.buildTherapySession(routine: routine)
        case .balanceSession(let exercise, let settings):
            component.sessionBuilder.buildBalanceSession(exercise: exercise, settings: settings)
        case .fingerSession:
            component.sessionBuilder.buildFingerSession()
        case .fingerSessionComplete:
            component.sessionBuilder.buildFingerSessionComplete()
        case .planNext:
            let viewModel: some DailyPlanNextViewModelProtocol = DailyPlanNextViewModel(
                plan: component.dailyPlan,
                audio: component.audio
            )

            TMDailyPlanNextView(viewModel: viewModel, builder: self)
        }
    }
}
