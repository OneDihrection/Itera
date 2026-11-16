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

    let permissions: PermissionManager
    let tracking = BodyTrackingService()
    let audio: SessionAudioService
    let buttonClick: ButtonClickPlayer

    // MARK: - Repositories

    let sessions: any SessionRepository
    /// Finger and forearm sessions share one folder, so this repository reads any session's
    /// key-repetition replays.
    let fingerReplayRepository: any FingerSessionRepository

    // MARK: - Shared models

    let fingers: FingerHomeViewModel
    let armRoutine: RoutineViewModel
    let taskRoutine: RoutineViewModel
    let fingerSessions: FingerSessionLauncher
    let historyRecovery: any HistoryRecovering
    /// Today's plan across programs; Beranda shows it and finishing sessions report to it.
    let dailyPlan: DailyPlanViewModel

    // MARK: - Routers

    /// Beranda's sheet, plan intro and full-screen cover; shared by the plan and its sessions.
    let homeRouter = HomeRouter()
    /// Concrete because `RootViewModel` wires it; features receive `tabRouter`.
    private let tabs = TabRouter()

    init(permissions: PermissionManager) {
        self.permissions = permissions

        let audio = SessionAudioService()
        let guidanceAudio = GuidanceAudioService()
        self.audio = audio
        buttonClick = ButtonClickPlayer(guidance: guidanceAudio, narration: audio)

        let directory = URL.applicationSupportDirectory.appendingPathComponent(
            "Sessions",
            isDirectory: true
        )
        sessions = LocalSessionRepository(directory: directory)
        historyRecovery = SessionHistoryRecovery(sessions: sessions)

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

        fingerSessions = FingerSessionLauncher(
            fingers: fingers,
            forearm: forearm,
            camera: HandCameraService(),
            audio: guidanceAudio,
            permissions: permissions,
            fingerRepository: fingerRepository,
            forearmRepository: forearmRepository
        )

        dailyPlan = DailyPlanViewModel(
            repository: LocalDailyPlanProgressRepository(),
            fingers: fingers,
            forearm: forearm,
            armRoutine: armRoutine,
            taskRoutine: taskRoutine,
            fingerSessions: fingerSessions,
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

    // MARK: - Feature builders

    lazy var historyBuilder = HistoryBuilder(dependency: self)
    lazy var sessionBuilder = TherapySessionBuilder(dependency: self)
    lazy var homeBuilder = HomeBuilder(dependency: self)

    // MARK: - Root

    /// Created once: it wires the tab router to its selection, so a rebuilt root must not
    /// replace it.
    lazy var rootViewModel = RootViewModel(
        router: tabs,
        playButtonClick: { [unowned self] in
            buttonClick.play()
        }
    )

    // MARK: - App lifecycle

    /// Finalizes a session interrupted by termination, once per launch.
    func recoverHistory() async {
        await historyRecovery.recoverHistory()
    }

    /// Re-reads authorization when the app returns to the foreground.
    func refreshPermissions() {
        permissions.refresh()
    }

    #if DEBUG
    /// Opens a plan intro named by the `intro:` launch argument.
    func openDebugIntroIfRequested() {
        DebugScreenLauncher.openIntroIfRequested(plan: dailyPlan)
    }
    #endif
}
