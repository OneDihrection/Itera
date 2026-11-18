//
//  HistoryBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// What the Progress tab needs from its parent.
@MainActor
protocol HistoryDependency {
    var fingers: FingerHomeViewModel { get }
    /// Arm, towel and Balancing summaries.
    var sessions: any SessionRepository { get }
    /// Reads any finger or forearm session's key-repetition replays.
    var fingerReplayRepository: any FingerSessionRepository { get }
}

/// What the reports list builds inside itself: its rows, and the pages it pushes.
protocol HistoryContentBuildable {
    associatedtype CellContent: View
    associatedtype FingerReportScreen: View
    associatedtype SessionReportScreen: View

    @ViewBuilder @MainActor func buildFingerReport(id: UUID) -> FingerReportScreen
    @ViewBuilder @MainActor func buildSessionReport(id: UUID) -> SessionReportScreen
    @ViewBuilder @MainActor func buildCell(entry: HistoryEntry) -> CellContent
}

@MainActor
final class HistoryBuilder: HistoryContentBuildable {
    private let dependency: any HistoryDependency
    /// One router for the tab's single stack.
    private let router = HistoryRouter()

    /// Created once, so a rebuilt root keeps its loaded history. The stack path lives in the
    /// router.
    private lazy var reportsViewModel = ReportsViewModel(
        home: dependency.fingers,
        armReports: TaskReportsViewModel(repository: dependency.sessions),
        router: router
    )

    init(dependency: any HistoryDependency) {
        self.dependency = dependency
    }

    @ViewBuilder func buildReports() -> some View {
        let viewModel: some ReportsViewModelProtocol = reportsViewModel

        TMFingerReportsView(viewModel: viewModel, builder: self)
    }

    @ViewBuilder func buildFingerReport(id: UUID) -> some View {
        let viewModel: some FingerReportDetailViewModelProtocol = FingerReportDetailViewModel(
            id: id,
            home: dependency.fingers,
            replays: FingerReplayViewModel(
                sessionID: id,
                repository: dependency.fingerReplayRepository
            ),
            router: router
        )

        TMFingerReportDetailView(viewModel: viewModel)
    }

    @ViewBuilder func buildSessionReport(id: UUID) -> some View {
        let viewModel: some SessionReportViewModelProtocol = SessionReportViewModel(
            sessionID: id,
            repository: dependency.sessions,
            router: router
        )

        TMSessionReportView(viewModel: viewModel)
            .environment(\.locale, AppLanguage.selected.locale)
    }

    /// No tap closure: the router is injected, so the row handles navigation itself.
    @ViewBuilder func buildCell(entry: HistoryEntry) -> some View {
        let viewModel: some HistoryCellViewModelProtocol = HistoryCellViewModel(
            entry: entry,
            router: router
        )

        TMHistoryCellView(viewModel: viewModel)
    }
}
