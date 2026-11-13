//
//  FingerReplayViewModel.swift
//  Itera
//
//  Created by dimaswisodewo on 13/11/2026.
//

import Foundation
import Observation

/// Loads one finger session's key-repetition hand replays and clips for its report.
@MainActor
@Observable
final class FingerReplayViewModel {
    /// Below this share of usable frames a replay is flagged as unclear.
    private static let lowTrackingCoverage = 0.5

    let sessionID: UUID
    /// The replay file exists but could not be read; the session's results are still shown.
    private(set) var replaysUnavailable = false
    private var keyReps: [FingerKeyReps] = []
    private var clipURLs: [FingerRepClipKey: URL] = [:]
    @ObservationIgnored private let repository: any FingerSessionRepository

    init(sessionID: UUID, repository: any FingerSessionRepository) {
        self.sessionID = sessionID
        self.repository = repository
    }

    func load() async {
        do {
            keyReps = try await repository.keyReps(sessionID: sessionID)
            replaysUnavailable = false
        } catch {
            keyReps = []
            replaysUnavailable = true
        }

        clipURLs = await repository.repClipURLs(sessionID: sessionID)
    }

    /// Recorded sets of `exercise`, in set order.
    func sets(for exercise: FingerExercise) -> [FingerKeyReps] {
        keyReps
            .filter { $0.exercise == exercise }
            .sorted { $0.setNumber < $1.setNumber }
    }

    /// The set's key repetitions, in repetition order.
    func reps(in set: FingerKeyReps) -> [KeyRep] {
        set.reps.sorted { $0.metrics.repNumber < $1.metrics.repNumber }
    }

    func clipURL(for rep: KeyRep, in set: FingerKeyReps) -> URL? {
        clipURLs[FingerRepClipKey(exercise: set.exercise, setNumber: set.setNumber, repNumber: rep.metrics.repNumber)]
    }

    func isTrackingLow(_ rep: KeyRep) -> Bool {
        rep.metrics.trackingCoverage < Self.lowTrackingCoverage
    }
}
