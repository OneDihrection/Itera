//
//  HistoryBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// Builds the Progress tab's root.
protocol HistoryBuildable {
    associatedtype ReportsScreen: View

    @ViewBuilder @MainActor func buildReports() -> ReportsScreen
}

/// The pages the reports list can push onto its stack.
protocol HistoryContentBuildable {
    associatedtype FingerReportScreen: View
    associatedtype SessionReportScreen: View

    @ViewBuilder @MainActor func buildFingerReport(id: UUID) -> FingerReportScreen
    @ViewBuilder @MainActor func buildSessionReport(id: UUID) -> SessionReportScreen
}

@MainActor
final class HistoryBuilder: HistoryBuildable, HistoryContentBuildable {
    private let component: HistoryComponent

    init(component: HistoryComponent) {
        self.component = component
    }

    @ViewBuilder func buildReports() -> some View {
        let viewModel: some ReportsViewModelProtocol = component.reportsViewModel

        TMFingerReportsView(viewModel: viewModel, builder: self)
    }

    @ViewBuilder func buildFingerReport(id: UUID) -> some View {
        let viewModel: some FingerReportDetailViewModelProtocol = FingerReportDetailViewModel(
            id: id,
            home: component.fingers,
            replayRepository: component.fingerReplayRepository,
            router: component.router
        )

        TMFingerReportDetailView(viewModel: viewModel)
    }

    @ViewBuilder func buildSessionReport(id: UUID) -> some View {
        let viewModel: some SessionReportViewModelProtocol = SessionReportViewModel(
            sessionID: id,
            repository: component.sessions,
            router: component.router
        )

        TMSessionReportView(viewModel: viewModel)
            .environment(\.locale, AppLanguage.selected.locale)
    }
}
