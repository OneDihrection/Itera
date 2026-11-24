//
//  AppComponent.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

/// The root component: constructs every shared service, repository and model once and seeds each
/// feature's builder by conforming to that feature's dependency protocol.
///
/// Features receive only their own dependency, builder and router; this root is never placed in
/// the environment or handed to feature code (SYSTEM_DESIGN §4 and "Inject services through
/// initializers").
@MainActor
final class AppComponent: HistoryDependency, HomeDependency, TherapySessionDependency {
    // MARK: - Services

    let permissionService: PermissionService
    let trackingService = BodyTrackingService()
    let audioService: SessionAudioService
    let buttonClickService: ButtonClickService

    // MARK: - Repositories

    let sessions: any SessionRepository
    /// Finger and forearm sessions share one folder, so this repository reads any session's
    /// key-repetition replays.
    let fingerReplayRepository: any FingerSessionRepository
    /// One actor for the plan's progress file: the plan writes today's entry and the Progress
    /// calendar reads every day, serialized on the same actor.
    private let planProgressRepository = LocalDailyPlanProgressRepository()

    // MARK: - Shared models

    let fingers: FingerHomeViewModel
    let armRoutine: RoutineViewModel
    let taskRoutine: RoutineViewModel
    let fingerSessionService: FingerSessionService
    let historyRecoveryService: any HistoryRecoveryServiceProtocol
    /// Today's plan across programs; Beranda shows it and finishing sessions report to it.
    let dailyPlan: DailyPlanViewModel

    // MARK: - Routers

    /// Beranda's sheet, plan intro and full-screen cover; shared by the plan and its sessions.
    let homeRouter = HomeRouter()
    /// Concrete because `RootViewModel` forwards its selection; features receive `tabRouter`.
    private let tabs = TabRouter()

    init(permissionService: PermissionService) {
        self.permissionService = permissionService

        let audioService = SessionAudioService()
        let guidanceAudioService = GuidanceAudioService()
        self.audioService = audioService
        buttonClickService = ButtonClickService(
            guidanceAudioService: guidanceAudioService,
            audioService: audioService
        )

        let directory = URL.applicationSupportDirectory.appendingPathComponent(
            "Sessions",
            isDirectory: true
        )
        sessions = LocalSessionRepository(directory: directory)
        historyRecoveryService = HistoryRecoveryService(sessions: sessions)

        armRoutine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines.json")
        ))
        taskRoutine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines-task-oriented.json")
        ))

        let fingerRepository = LocalFingerSessionRepository()
        fingerReplayRepository = fingerRepository
        fingers = FingerHomeViewModel(
            repository: fingerRepository,
            routineRepository: LocalFingerRoutineRepository()
        )

        let forearmRepository = LocalFingerSessionRepository(category: .forearm)
        let forearm = FingerHomeViewModel(
            category: .forearm,
            repository: forearmRepository,
            routineRepository: LocalFingerRoutineRepository(category: .forearm)
        )

        fingerSessionService = FingerSessionService(
            fingers: fingers,
            forearm: forearm,
            cameraService: HandCameraService(),
            guidanceAudioService: guidanceAudioService,
            permissionService: permissionService,
            fingerRepository: fingerRepository,
            forearmRepository: forearmRepository
        )

        dailyPlan = DailyPlanViewModel(
            repository: planProgressRepository,
            fingers: fingers,
            forearm: forearm,
            armRoutine: armRoutine,
            taskRoutine: taskRoutine,
            fingerSessionService: fingerSessionService,
            router: homeRouter
        )

    }

    var tabRouter: any TabRouterProtocol {
        tabs
    }

    /// Session pages live in the plan's cover, so they use the plan's router.
    var sessionRouter: any SessionRouterProtocol {
        homeRouter
    }

    /// Sessions report to today's plan without depending on Home.
    var planReporting: any DailyPlanSessionReporting {
        dailyPlan
    }

    /// The Progress calendar reads the plan's saved days through History's own contract.
    var planHistoryRepository: any DailyPlanHistoryRepository {
        planProgressRepository
    }

    /// Beranda reads earlier daily-plan entries to distinguish completed and missed dates.
    var dailyPlanProgressRepository: any DailyPlanProgressRepository {
        planProgressRepository
    }

    // MARK: - Feature builders

    lazy var historyBuilder = HistoryBuilder(dependency: self)
    lazy var sessionBuilder = TherapySessionBuilder(dependency: self)
    lazy var homeBuilder = HomeBuilder(dependency: self)

    // MARK: - Root

    /// Created once, so a rebuilt root keeps the same model. The selected tab lives in the tab
    /// router.
    lazy var rootViewModel = RootViewModel(
        router: tabs,
        playButtonClick: { [unowned self] in
            buttonClickService.play()
        }
    )

    // MARK: - App lifecycle

    /// Finalizes a session interrupted by termination, once per launch.
    func recoverHistory() async {
        await historyRecoveryService.recoverHistory()
    }

    /// Re-reads authorization when the app returns to the foreground.
    func refreshPermissions() {
        permissionService.refresh()
    }

    #if DEBUG
    /// Opens a plan intro named by the `intro:` launch argument, or Settings for `settings`.
    func openDebugIntroIfRequested() {
        DebugScreenLauncher.openIntroIfRequested(plan: dailyPlan)
        DebugScreenLauncher.openSettingsIfRequested(router: homeRouter)
    }
    #endif
}
