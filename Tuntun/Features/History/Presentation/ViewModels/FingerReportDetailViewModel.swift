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
    /// Present once the key-repetition replays have loaded.
    var replays: FingerReplayViewModel? { get }

    func load() async
    func delete(_ summary: FingerSessionSummary) async
}

/// One saved finger or forearm session with its key-repetition replays.
@MainActor
@Observable
final class FingerReportDetailViewModel: FingerReportDetailViewModelProtocol {
    private(set) var replays: FingerReplayViewModel?

    @ObservationIgnored private let id: UUID
    @ObservationIgnored private let home: FingerHomeViewModel
    @ObservationIgnored private let replayRepository: any FingerSessionRepository
    @ObservationIgnored private let router: any HistoryRouterProtocol

    init(
        id: UUID,
        home: FingerHomeViewModel,
        replayRepository: any FingerSessionRepository,
        router: any HistoryRouterProtocol
    ) {
        self.id = id
        self.home = home
        self.replayRepository = replayRepository
        self.router = router
    }

    var summary: FingerSessionSummary? {
        home.history.first { $0.id == id }
    }

    func load() async {
        await home.refresh()

        let replays = FingerReplayViewModel(sessionID: id, repository: replayRepository)
        await replays.load()
        self.replays = replays
    }

    /// Returns to the reports list once the session is gone.
    func delete(_ summary: FingerSessionSummary) async {
        await home.delete(summary)

        guard home.errorKey == nil else {
            return
        }

        router.popToRoot()
    }
}
