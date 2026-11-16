//
//  HomeComponent.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

/// What Beranda, its settings, today's plan and the plan's sessions need from their parent.
@MainActor
protocol HomeDependency {
    var fingers: FingerHomeViewModel { get }
    var armRoutine: RoutineViewModel { get }
    var taskRoutine: RoutineViewModel { get }
    var dailyPlan: DailyPlanViewModel { get }
    var fingerSessions: FingerSessionLauncher { get }
    var tracking: BodyTrackingService { get }
    var audio: SessionAudioService { get }
    var sessions: any SessionRepository { get }
    var permissions: PermissionManager { get }
    /// Readiness waits for interrupted-session recovery before therapy can start.
    var historyRecovery: any HistoryRecovering { get }
    /// Shared with `DailyPlanViewModel`, which drives the plan's navigation.
    var homeRouter: HomeRouter { get }
    var tabRouter: any TabRouterProtocol { get }
}

/// Seeds the session pages' component, as Beranda's plan cover presents them.
@MainActor
final class HomeComponent: Component<HomeDependency>, TherapySessionDependency {
    let fingers: FingerHomeViewModel
    let armRoutine: RoutineViewModel
    let taskRoutine: RoutineViewModel
    let dailyPlan: DailyPlanViewModel
    let fingerSessions: FingerSessionLauncher
    let tracking: BodyTrackingService
    let audio: SessionAudioService
    let sessions: any SessionRepository
    let permissions: PermissionManager
    let historyRecovery: any HistoryRecovering
    let homeRouter: HomeRouter
    let tabRouter: any TabRouterProtocol

    /// Created once: it wires the router's hooks to its stack, sheet and cover, so a rebuilt
    /// root must not replace it.
    lazy var homeViewModel = HomeScreenViewModel(
        fingers: fingers,
        armRoutine: armRoutine,
        taskRoutine: taskRoutine,
        plan: dailyPlan,
        router: homeRouter
    )

    lazy var sessionBuilder = TherapySessionBuilder(
        component: TherapySessionComponent(dependency: self)
    )

    init(dependency: HomeDependency) {
        self.fingers = dependency.fingers
        self.armRoutine = dependency.armRoutine
        self.taskRoutine = dependency.taskRoutine
        self.dailyPlan = dependency.dailyPlan
        self.fingerSessions = dependency.fingerSessions
        self.tracking = dependency.tracking
        self.audio = dependency.audio
        self.sessions = dependency.sessions
        self.permissions = dependency.permissions
        self.historyRecovery = dependency.historyRecovery
        self.homeRouter = dependency.homeRouter
        self.tabRouter = dependency.tabRouter
        super.init(with: dependency)
    }

    var sessionRouter: any SessionRouterProtocol {
        homeRouter
    }
}
