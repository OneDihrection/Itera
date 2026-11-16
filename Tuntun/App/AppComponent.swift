//
//  AppComponent.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation
import Observation
import SwiftUI

/// The root component: constructs every shared service, repository and model once and seeds each
/// feature's component by conforming to that feature's dependency protocol.
///
/// Features receive only their own component, builder and router; this root is never placed in
/// the environment or handed to feature code (SYSTEM_DESIGN §3, "Inject services through
/// initializers").
@MainActor
final class AppComponent: Component<Void>, HistoryDependency, HomeDependency {
    // MARK: - Services

    let permissions: PermissionManager
    let tracking = BodyTrackingService()
    let audio = SessionAudioService()
    private let fingerAudio = GuidanceAudioService()

    // MARK: - Repositories

    let sessions: any SessionRepository
    /// Finger and forearm sessions share one folder, so this repository reads any session's
    /// key-repetition replays.
    private let fingerRepository: any FingerSessionRepository

    // MARK: - Shared models

    let fingers: FingerHomeViewModel
    private let forearm: FingerHomeViewModel
    let armRoutine: RoutineViewModel
    let taskRoutine: RoutineViewModel
    let fingerSessions: FingerSessionLauncher
    private let recovery: SessionHistoryRecovery
    /// Today's plan across programs; Beranda shows it and finishing sessions report to it.
    let dailyPlan: DailyPlanViewModel

    // MARK: - Routers

    /// Beranda's stack, sheet and plan cover; shared by the plan and its sessions.
    let homeRouter = HomeRouter()
    /// One tab router for the app's single tab bar.
    private let tabs = TabRouter()

    init(permissions: PermissionManager) {
        self.permissions = permissions

        let directory = URL.applicationSupportDirectory.appendingPathComponent(
            "Sessions",
            isDirectory: true
        )
        sessions = LocalSessionRepository(directory: directory)
        recovery = SessionHistoryRecovery(sessions: sessions)

        armRoutine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines.json")
        ))
        taskRoutine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines-task-oriented.json")
        ))

        let fingerRepository = LocalFingerSessionRepository()
        self.fingerRepository = fingerRepository
        fingers = FingerHomeViewModel(
            repository: fingerRepository,
            routineRepository: LocalFingerRoutineRepository()
        )

        let forearmRepository = LocalFingerSessionRepository(category: .forearm)
        forearm = FingerHomeViewModel(
            category: .forearm,
            repository: forearmRepository,
            routineRepository: LocalFingerRoutineRepository(category: .forearm)
        )

        fingerSessions = FingerSessionLauncher(
            fingers: fingers,
            forearm: forearm,
            camera: HandCameraService(),
            audio: fingerAudio,
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

        super.init(with: ())
    }

    var fingerReplayRepository: any FingerSessionRepository {
        fingerRepository
    }

    var historyRecovery: any HistoryRecovering {
        recovery
    }

    var tabRouter: any TabRouterProtocol {
        tabs
    }

    // MARK: - Feature builders

    lazy var historyBuilder = HistoryBuilder(component: HistoryComponent(dependency: self))
    lazy var homeBuilder = HomeBuilder(component: HomeComponent(dependency: self))

    // MARK: - Root

    /// Created once: it wires the tab router to its selection, so a rebuilt root must not
    /// replace it.
    private lazy var rootViewModel = RootViewModel(
        router: tabs,
        playButtonClick: { [unowned self] in
            playButtonClick()
        }
    )

    /// The tab root. Each tab's root screen owns its own navigation stack.
    @ViewBuilder func buildRoot() -> some View {
        let viewModel: some RootViewModelProtocol = rootViewModel

        RootView(
            viewModel: viewModel,
            home: homeBuilder.buildHome(),
            reports: historyBuilder.buildReports()
        )
    }

    // MARK: - App lifecycle

    func recoverHistory() async {
        await recovery.recoverHistory()
    }

    func refreshPermissions() {
        permissions.refresh()
    }

    func playButtonClick() {
        guard UserDefaults.standard.object(forKey: PracticePreferences.buttonSounds) as? Bool ?? true else {
            return
        }

        // A tap sound never lands on top of narration from a running session.
        guard !audio.isNarrating else {
            return
        }

        fingerAudio.playButtonClick()
    }

    #if DEBUG
    func openDebugIntroIfRequested() {
        DebugScreenLauncher.openIntroIfRequested(plan: dailyPlan)
    }
    #endif
}
