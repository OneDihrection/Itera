//
//  AppDependencies.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Observation

@MainActor
@Observable
final class AppDependencies {
    let progress: PracticeProgressViewModel
    let home: FingerHomeViewModel
    private(set) var session: FingerSessionViewModel?
    let permissions: PermissionManager
    @ObservationIgnored private let camera = HandCameraService()
    @ObservationIgnored private let audio = GuidanceAudioService()
    @ObservationIgnored private let repository: any FingerSessionRepository

    init(permissions: PermissionManager) {
        self.permissions = permissions
        let repository = LocalFingerSessionRepository()
        self.repository = repository
        home = FingerHomeViewModel(repository: repository, routineRepository: LocalFingerRoutineRepository())
        progress = PracticeProgressViewModel(history: repository, repository: LocalAchievementRepository())
    }

    func playButtonClick() {
        audio.playButtonClick()
    }

    func prepareSession(continuing: Bool = false) {
        let checkpoint = continuing ? home.checkpoint : nil
        session = FingerSessionViewModel(
            routine: checkpoint?.routine ?? home.routine, checkpoint: checkpoint,
            camera: camera, audio: audio, permissions: permissions, repository: repository
        )
    }
}
