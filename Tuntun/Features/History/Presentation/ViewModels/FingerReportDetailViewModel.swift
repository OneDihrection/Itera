//
//  FingerReportDetailViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

@MainActor
protocol FingerReportDetailViewModelProtocol: AnyObject, Observable {
    var summary: FingerSessionSummary? { get }
    /// True once the key-repetition replays have been read, successfully or not.
    var replaysLoaded: Bool { get }
    /// The replay file exists but could not be read; the session's results are still shown.
    var replaysUnavailable: Bool { get }

    func load() async
    func delete(_ summary: FingerSessionSummary) async
    /// Recorded sets of `exercise`, in set order.
    func replaySets(for exercise: FingerExercise) -> [FingerKeyReps]
    func reps(in set: FingerKeyReps) -> [KeyRep]
    func clipURL(for rep: KeyRep, in set: FingerKeyReps) -> URL?
    func isTrackingLow(_ rep: KeyRep) -> Bool
}

/// One saved finger or forearm session with its key-repetition replays.
@MainActor
@Observable
final class FingerReportDetailViewModel: FingerReportDetailViewModelProtocol {
    private(set) var replaysLoaded = false

    @ObservationIgnored private let id: UUID
    @ObservationIgnored private let home: FingerHomeViewModel
    private let replays: FingerReplayViewModel
    @ObservationIgnored private let router: any HistoryRouterProtocol

    init(
        id: UUID,
        home: FingerHomeViewModel,
        replays: FingerReplayViewModel,
        router: any HistoryRouterProtocol
    ) {
        self.id = id
        self.home = home
        self.replays = replays
        self.router = router
    }

    var summary: FingerSessionSummary? {
        home.history.first { $0.id == id }
    }

    var replaysUnavailable: Bool {
        replays.replaysUnavailable
    }

    func load() async {
        await home.refresh()
        await replays.load()
        replaysLoaded = true
    }

    /// Returns to the reports list once the session is gone.
    func delete(_ summary: FingerSessionSummary) async {
        await home.delete(summary)

        guard home.errorKey == nil else {
            return
        }

        router.popToRoot()
    }

    // MARK: - Replays

    func replaySets(for exercise: FingerExercise) -> [FingerKeyReps] {
        replays.sets(for: exercise)
    }

    func reps(in set: FingerKeyReps) -> [KeyRep] {
        replays.reps(in: set)
    }

    func clipURL(for rep: KeyRep, in set: FingerKeyReps) -> URL? {
        replays.clipURL(for: rep, in: set)
    }

    func isTrackingLow(_ rep: KeyRep) -> Bool {
        replays.isTrackingLow(rep)
    }
}
