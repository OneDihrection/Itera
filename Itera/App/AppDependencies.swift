//
//  AppDependencies.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppDependencies: HistoryRecovering {
    let tracking = BodyTrackingService()
    let audio = SessionAudioService()
    let routine: RoutineViewModel
    var selectedRoutine = Routine.demo()
    let sessions: any SessionRepository
    private(set) var recoveryFailure: String?
    private(set) var recovering = true
    private var didRecover = false

    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent(
            "Sessions", isDirectory: true)
        sessions = LocalSessionRepository(directory: directory)
        routine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines.json")
        ))
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
