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
    let forearm: FingerHomeViewModel
    private(set) var session: FingerSessionViewModel?
    let permissions: PermissionManager
    @ObservationIgnored private let camera = HandCameraService()
    @ObservationIgnored private let fingerAudio = GuidanceAudioService()
    @ObservationIgnored private let repository: any FingerSessionRepository
    @ObservationIgnored private let forearmRepository: any FingerSessionRepository

    let tracking = BodyTrackingService()
    let audio = SessionAudioService()
    let routine: RoutineViewModel
    let trunkRoutine: RoutineViewModel
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
        trunkRoutine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines-trunk.json")
        ))

        let repository = LocalFingerSessionRepository()
        self.repository = repository
        home = FingerHomeViewModel(repository: repository, routineRepository: LocalFingerRoutineRepository())
        let forearmRepository = LocalFingerSessionRepository(category: .forearm)
        self.forearmRepository = forearmRepository
        forearm = FingerHomeViewModel(
            category: .forearm, repository: forearmRepository,
            routineRepository: LocalFingerRoutineRepository(category: .forearm)
        )
        progress = PracticeProgressViewModel(history: repository, repository: LocalAchievementRepository())
    }

    func playButtonClick() {
        guard UserDefaults.standard.object(forKey: PracticePreferences.buttonSounds) as? Bool ?? true else {
            return
        }
        fingerAudio.playButtonClick()
    }

    func playAchievementCue() {
        guard UserDefaults.standard.object(forKey: PracticePreferences.celebrationSounds) as? Bool ?? true else {
            return
        }
        fingerAudio.playAchievementCue()
    }

    func routineModel(for category: TherapyCategory) -> RoutineViewModel {
        category == .arm ? routine : trunkRoutine
    }

    func homeModel(for category: ExerciseCategory) -> FingerHomeViewModel {
        category == .fingers ? home : forearm
    }

    func refreshHomes() async {
        await home.refresh()
        await forearm.refresh()
    }

    func prepareSession(category: ExerciseCategory = .fingers, continuing: Bool = false) {
        let model = homeModel(for: category)
        let checkpoint = continuing ? model.checkpoint : nil
        session = FingerSessionViewModel(
            routine: checkpoint?.routine ?? model.routine, checkpoint: checkpoint,
            camera: camera, audio: fingerAudio, permissions: permissions,
            repository: category == .fingers ? repository : forearmRepository
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
