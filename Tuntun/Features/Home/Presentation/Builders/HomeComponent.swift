//
//  HomeComponent.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

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

@MainActor
final class HomeComponent: Component<HomeDependency> {
    let fingers: FingerHomeViewModel
    let armRoutine: RoutineViewModel
    let taskRoutine: RoutineViewModel
    let dailyPlan: DailyPlanViewModel
    let audio: SessionAudioService
    let permissions: PermissionManager
    let historyRecovery: any HistoryRecovering
    let homeRouter: HomeRouter
    let planRouter: PlanRouter
    let sessionBuilder: TherapySessionBuilder

    /// Created once: it wires the router's hooks to its stack, sheet and cover, so a rebuilt
    /// root must not replace it.
    lazy var homeViewModel = HomeScreenViewModel(
        fingers: fingers,
        armRoutine: armRoutine,
        taskRoutine: taskRoutine,
        plan: dailyPlan,
        homeRouter: homeRouter,
        planRouter: planRouter
    )

    init(dependency: HomeDependency) {
        self.fingers = dependency.fingers
        self.armRoutine = dependency.armRoutine
        self.taskRoutine = dependency.taskRoutine
        self.dailyPlan = dependency.dailyPlan
        self.audio = dependency.audio
        self.permissions = dependency.permissions
        self.historyRecovery = dependency.historyRecovery
        self.homeRouter = dependency.homeRouter
        self.planRouter = dependency.planRouter
        self.sessionBuilder = dependency.sessionBuilder
        super.init(with: dependency)
    }
}
