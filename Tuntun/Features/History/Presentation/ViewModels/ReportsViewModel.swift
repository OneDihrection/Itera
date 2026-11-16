//
//  ReportsViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

@MainActor
protocol ReportsViewModelProtocol: AnyObject, Observable {
    var path: [HistoryRoute] { get set }
    var fingerHistory: [FingerSessionSummary] { get }
    /// Arm practice and the Balancing exercises, saved by the session repository.
    var armHistory: [SessionSummary] { get }
    var errorKey: String? { get }
    var deletingHistory: Bool { get }

    func refresh() async
    /// Deletes every saved session; true when both stores succeeded.
    func deleteHistory() async -> Bool
}

/// The Progress tab: owns its navigation stack and joins finger and arm history. Rows navigate
/// through their own view models.
@MainActor
@Observable
final class ReportsViewModel: ReportsViewModelProtocol {
    var path: [HistoryRoute] = []
    private(set) var deletingHistory = false

    @ObservationIgnored private let home: FingerHomeViewModel
    @ObservationIgnored private let router: HistoryRouter
    private let armReports: TaskReportsViewModel

    init(
        home: FingerHomeViewModel,
        armReports: TaskReportsViewModel,
        router: HistoryRouter
    ) {
        self.home = home
        self.router = router
        self.armReports = armReports

        router.push = { [weak self] route in
            self?.path.append(route)
        }
        router.popLast = { [weak self] in
            guard let self, !path.isEmpty else {
                return
            }

            path.removeLast()
        }
        router.reset = { [weak self] in
            self?.path.removeAll()
        }
    }

    var fingerHistory: [FingerSessionSummary] {
        home.history
    }

    var armHistory: [SessionSummary] {
        armReports.summaries
    }

    var errorKey: String? {
        home.errorKey ?? armReports.errorKey
    }

    func refresh() async {
        guard !deletingHistory else {
            return
        }

        await home.refresh()
        await armReports.load()
    }

    func deleteHistory() async -> Bool {
        guard !deletingHistory else {
            return false
        }

        deletingHistory = true
        defer { deletingHistory = false }

        await home.deleteHistory()
        await armReports.deleteAll()

        return errorKey == nil
    }
}
