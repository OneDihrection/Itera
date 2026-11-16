//
//  FingerSessionLauncher.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

/// The open finger session the live page shows.
@MainActor
protocol FingerSessionLaunching: AnyObject, Observable {
    associatedtype Session: FingerSessionViewModelProtocol

    var session: Session? { get }
}

/// Prepares finger and forearm sessions and keeps the open one.
///
/// The live session page and its closing page are separate routes, so the session model
/// outlives each of them here until the next session replaces it.
@MainActor
@Observable
final class FingerSessionLauncher: FingerSessionLaunching {
    private(set) var session: FingerSessionViewModel?

    @ObservationIgnored private let fingers: FingerHomeViewModel
    @ObservationIgnored private let forearm: FingerHomeViewModel
    @ObservationIgnored private let camera: HandCameraService
    @ObservationIgnored private let audio: GuidanceAudioService
    @ObservationIgnored private let permissions: PermissionManager
    @ObservationIgnored private let fingerRepository: any FingerSessionRepository
    @ObservationIgnored private let forearmRepository: any FingerSessionRepository

    init(
        fingers: FingerHomeViewModel,
        forearm: FingerHomeViewModel,
        camera: HandCameraService,
        audio: GuidanceAudioService,
        permissions: PermissionManager,
        fingerRepository: any FingerSessionRepository,
        forearmRepository: any FingerSessionRepository
    ) {
        self.fingers = fingers
        self.forearm = forearm
        self.camera = camera
        self.audio = audio
        self.permissions = permissions
        self.fingerRepository = fingerRepository
        self.forearmRepository = forearmRepository
    }

    /// - Parameters:
    ///   - only: one exercise of the category to run alone, as a daily-plan item does.
    ///   - sets: replaces the saved sets for this session only, as `side` does.
    ///   - repetitions: replaces the saved repetitions for this session only.
    func prepare(
        category: ExerciseCategory = .fingers,
        continuing: Bool = false,
        only: FingerExercise? = nil,
        side: HandSide? = nil,
        sets: Int? = nil,
        repetitions: Int? = nil
    ) {
        let model = category == .fingers ? fingers : forearm
        let checkpoint = continuing ? model.checkpoint : nil
        var routine = checkpoint?.routine ?? model.routine

        if checkpoint == nil {
            routine.only = only
            routine.side = side ?? routine.side
            routine.sets = sets ?? routine.sets
            routine.repetitions = repetitions ?? routine.repetitions
        }

        session = FingerSessionViewModel(
            routine: routine,
            checkpoint: checkpoint,
            camera: camera,
            audio: audio,
            permissions: permissions,
            repository: category == .fingers ? fingerRepository : forearmRepository
        )
    }
}
