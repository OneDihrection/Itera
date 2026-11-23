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
    /// The daily plan's saved days, for the calendar's completed days.
    var planHistoryRepository: any DailyPlanHistoryRepository { get }
}

/// The pages the Progress tab pushes onto its stack, and the exercise detail panel's content.
protocol HistoryContentBuildable {
    associatedtype FingerReportScreen: View
    associatedtype SessionReportScreen: View
    associatedtype PracticeDayScreen: View
    associatedtype ExerciseDetailContent: View

    @ViewBuilder @MainActor func buildFingerReport(id: UUID) -> FingerReportScreen
    @ViewBuilder @MainActor func buildSessionReport(id: UUID) -> SessionReportScreen
    @ViewBuilder @MainActor func buildPracticeDay(_ day: Date) -> PracticeDayScreen
    @ViewBuilder @MainActor func buildExerciseDetail(_ route: ExerciseDetailRoute) -> ExerciseDetailContent
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
        planHistoryRepository: dependency.planHistoryRepository,
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

    /// The day's exercises come from the history the Progress tab already loaded, and follow it.
    @ViewBuilder func buildPracticeDay(_ day: Date) -> some View {
        let viewModel: some PracticeDayViewModelProtocol = PracticeDayViewModel(
            day: day,
            history: reportsViewModel,
            router: router
        )

        TMPracticeDayView(viewModel: viewModel)
    }

    /// Reads the exercise's whole history, so the panel can compare the day with earlier sessions.
    @ViewBuilder func buildExerciseDetail(_ route: ExerciseDetailRoute) -> some View {
        let viewModel: some ExerciseDetailViewModelProtocol = ExerciseDetailViewModel(
            route: route,
            sessions: dependency.sessions,
            fingers: dependency.fingers,
            fingerReplayRepository: dependency.fingerReplayRepository,
            planHistoryRepository: dependency.planHistoryRepository,
            history: reportsViewModel,
            router: router
        )

        TMExerciseDetailView(viewModel: viewModel)
            .environment(\.locale, AppLanguage.selected.locale)
    }
}
