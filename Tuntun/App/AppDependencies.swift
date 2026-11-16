//
//  AppDependencies.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation
import Observation
import SwiftUI

/// The composition root: constructs every shared service, repository and model once, and
/// builds each page with only the dependencies it uses.
///
/// Pages receive their dependencies through initializers; this container is never placed in the
/// environment or handed to feature code (SYSTEM_DESIGN §3, "Inject services through
/// initializers").
@MainActor
final class AppDependencies {
    // MARK: - Services

    private let permissions: PermissionManager
    private let tracking = BodyTrackingService()
    private let audio = SessionAudioService()
    private let fingerAudio = GuidanceAudioService()

    // MARK: - Repositories

    private let sessions: any SessionRepository
    /// Finger and forearm sessions share one folder, so this repository reads any session's
    /// key-repetition replays.
    private let fingerRepository: any FingerSessionRepository

    // MARK: - Shared models

    private let fingers: FingerHomeViewModel
    private let forearm: FingerHomeViewModel
    private let armRoutine: RoutineViewModel
    private let taskRoutine: RoutineViewModel
    private let fingerSessions: FingerSessionLauncher
    private let historyRecovery: SessionHistoryRecovery
    /// Today's plan across programs; Beranda shows it and finishing sessions report to it.
    private let dailyPlan: DailyPlanViewModel

    init(permissions: PermissionManager) {
        self.permissions = permissions

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
            fingerSessions: fingerSessions
        )
    }

    // MARK: - App lifecycle

    func recoverHistory() async {
        await historyRecovery.recoverHistory()
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
    func openDebugIntroIfRequested(router: NavigationRouter) {
        DebugScreenLauncher.openIntroIfRequested(plan: dailyPlan, router: router)
    }
    #endif

    // MARK: - Home

    func makeHomeView() -> TMHomeView {
        TMHomeView(
            home: fingers,
            routine: armRoutine,
            taskRoutine: taskRoutine,
            plan: dailyPlan
        )
    }

    func makePracticePreferencesView() -> TMPracticePreferencesView {
        TMPracticePreferencesView(home: fingers, plan: dailyPlan)
    }

    func makeDailyPlanIntroView(
        itemID: String,
        countdownSeconds: Int? = nil,
        automatic: Bool = false
    ) -> TMDailyPlanIntroView {
        TMDailyPlanIntroView(
            itemID: itemID,
            countdownSeconds: countdownSeconds,
            automatic: automatic,
            plan: dailyPlan,
            audio: audio,
            permissions: permissions,
            history: historyRecovery
        )
    }

    func makeDailyPlanNextView() -> TMDailyPlanNextView {
        TMDailyPlanNextView(plan: dailyPlan, audio: audio) { [unowned self] itemID, countdownSeconds, automatic in
            makeDailyPlanIntroView(
                itemID: itemID,
                countdownSeconds: countdownSeconds,
                automatic: automatic
            )
        }
    }

    #if DEBUG
    func makeDebugPlanEditorView() -> TMDebugPlanEditorView {
        TMDebugPlanEditorView(plan: dailyPlan)
    }
    #endif

    // MARK: - History

    func makeFingerReportsView() -> TMFingerReportsView {
        TMFingerReportsView(home: fingers, sessions: sessions)
    }

    func makeFingerReportDetailView(id: UUID) -> TMFingerReportDetailView {
        TMFingerReportDetailView(id: id, home: fingers, replayRepository: fingerRepository)
    }

    func makeSessionReportView(id: UUID) -> TMSessionReportView {
        TMSessionReportView(model: SessionReportViewModel(sessionID: id, repository: sessions))
    }

    // MARK: - Sessions

    func makeTherapySessionView(routine: Routine) -> TMTherapySessionView {
        let model = TherapySessionViewModel(
            tracking: tracking,
            audio: audio,
            repository: sessions,
            routine: routine
        )

        return TMTherapySessionView(model: model, plan: dailyPlan, permissions: permissions)
    }

    #if DEBUG
    func makeTherapySessionView(fixture: SessionSnapshot) -> TMTherapySessionView {
        TMTherapySessionView(fixture: fixture, plan: dailyPlan, permissions: permissions)
    }
    #endif

    func makeBalanceSessionView(
        exercise: BalanceExercise,
        settings: BalancePracticeSettings
    ) -> TMBalanceSessionView {
        let model = BalanceSessionViewModel(
            tracking: tracking,
            audio: audio,
            repository: sessions,
            settings: settings,
            exercise: exercise
        )

        return TMBalanceSessionView(model: model, plan: dailyPlan, permissions: permissions)
    }

    func makeFingerSessionView() -> TMFingerSessionView {
        TMFingerSessionView(launcher: fingerSessions, plan: dailyPlan)
    }

    func makeFingerSessionCompleteView() -> TMFingerSessionCompleteView {
        TMFingerSessionCompleteView(launcher: fingerSessions, plan: dailyPlan, home: fingers)
    }
}
