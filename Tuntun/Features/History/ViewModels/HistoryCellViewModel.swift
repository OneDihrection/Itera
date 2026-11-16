//
//  HistoryCellViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

/// One row of "Riwayat latihan": finger and arm sessions are saved separately but listed together.
enum HistoryEntry: Identifiable {
    case finger(FingerSessionSummary)
    case arm(SessionSummary)

    var id: UUID {
        switch self {
        case .finger(let summary): return summary.id
        case .arm(let summary): return summary.id
        }
    }

    var date: Date {
        switch self {
        case .finger(let summary): return summary.started
        case .arm(let summary): return summary.startedAt
        }
    }
}

@MainActor
protocol HistoryCellViewModelProtocol: AnyObject, Observable {
    var entry: HistoryEntry { get }

    func onTap()
}

/// A history row opens its own report through the injected router.
@MainActor
@Observable
final class HistoryCellViewModel: HistoryCellViewModelProtocol {
    let entry: HistoryEntry

    @ObservationIgnored private let router: any HistoryRouterProtocol

    init(entry: HistoryEntry, router: any HistoryRouterProtocol) {
        self.entry = entry
        self.router = router
    }

    func onTap() {
        switch entry {
        case .finger(let summary):
            router.showFingerReport(id: summary.id)
        case .arm(let summary):
            router.showSessionReport(id: summary.id)
        }
    }
}
