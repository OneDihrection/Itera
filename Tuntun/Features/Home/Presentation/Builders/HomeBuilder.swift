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

/// What Beranda can push, present as a sheet, or show in its plan cover.
protocol HomeContentBuildable: PlanCoverBuildable {
    associatedtype DailyPlanIntroScreen: View
    associatedtype PracticePreferencesScreen: View

    @ViewBuilder @MainActor func buildDailyPlanIntro(itemID: String) -> DailyPlanIntroScreen
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

    @ViewBuilder func buildDailyPlanIntro(itemID: String) -> some View {
        makeDailyPlanIntro(itemID: itemID)
    }

    @ViewBuilder func buildPracticePreferences() -> some View {
        TMPracticePreferencesView(
            home: component.fingers,
            plan: component.dailyPlan,
            router: component.homeRouter,
            builder: self
        )
    }

    #if DEBUG
    @ViewBuilder func buildDebugPlanEditor() -> some View {
        TMDebugPlanEditorView(plan: component.dailyPlan)
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
            TMDailyPlanNextView(
                plan: component.dailyPlan,
                audio: component.audio
            ) { [unowned self] itemID, countdownSeconds, automatic in
                makeDailyPlanIntro(
                    itemID: itemID,
                    countdownSeconds: countdownSeconds,
                    automatic: automatic
                )
            }
        }
    }

    // MARK: - Helpers

    /// The intro is pushed from Beranda, and embedded after a rest by the next-exercise page.
    private func makeDailyPlanIntro(
        itemID: String,
        countdownSeconds: Int? = nil,
        automatic: Bool = false
    ) -> TMDailyPlanIntroView {
        TMDailyPlanIntroView(
            itemID: itemID,
            countdownSeconds: countdownSeconds,
            automatic: automatic,
            plan: component.dailyPlan,
            audio: component.audio,
            permissions: component.permissions,
            history: component.historyRecovery
        )
    }
}
