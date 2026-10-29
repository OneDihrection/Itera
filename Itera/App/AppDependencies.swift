//
//  AppDependencies.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppDependencies: HistoryRecovering {
    let progress: PracticeProgressViewModel
    let home: FingerHomeViewModel
    private(set) var session: FingerSessionViewModel?
    let permissions: PermissionManager
    @ObservationIgnored private let camera = HandCameraService()
    @ObservationIgnored private let fingerAudio = GuidanceAudioService()
    @ObservationIgnored private let repository: any FingerSessionRepository

    let tracking = BodyTrackingService()
    let audio = SessionAudioService()
    let routine: RoutineViewModel
    var selectedRoutine = Routine.demo()
    let sessions: any SessionRepository
    private(set) var recoveryFailure: String?
    private(set) var recovering = true
    private var didRecover = false

    init(permissions: PermissionManager) {
        self.permissions = permissions
        let directory = URL.applicationSupportDirectory.appendingPathComponent(
            "Sessions", isDirectory: true)
        sessions = LocalSessionRepository(directory: directory)
        routine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines.json")
        ))

        let repository = LocalFingerSessionRepository()
        self.repository = repository
        home = FingerHomeViewModel(repository: repository, routineRepository: LocalFingerRoutineRepository())
        progress = PracticeProgressViewModel(history: repository, repository: LocalAchievementRepository())
    }

    func playButtonClick() {
        fingerAudio.playButtonClick()
    }

    func prepareSession(continuing: Bool = false) {
        let checkpoint = continuing ? home.checkpoint : nil
        session = FingerSessionViewModel(
            routine: checkpoint?.routine ?? home.routine, checkpoint: checkpoint,
            camera: camera, audio: fingerAudio, permissions: permissions, repository: repository
        )
    }

    func recoverHistory() async {
        guard !didRecover else { return }
        recovering = true
        do {
            try await sessions.recoverInterrupted()
            recoveryFailure = nil
            didRecover = true
        } catch {
            recoveryFailure = error.localizedDescription
        }
        recovering = false
    }

    func makeSession() -> TherapySessionViewModel {
        TherapySessionViewModel(tracking: tracking, audio: audio, repository: sessions, routine: selectedRoutine)
    }
}
