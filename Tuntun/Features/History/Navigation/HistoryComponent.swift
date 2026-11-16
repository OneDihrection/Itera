//
//  HistoryComponent.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

/// What the Progress tab needs from its parent.
@MainActor
protocol HistoryDependency {
    var fingers: FingerHomeViewModel { get }
    /// Arm, towel and Balancing summaries.
    var sessions: any SessionRepository { get }
    /// Reads any finger or forearm session's key-repetition replays.
    var fingerReplayRepository: any FingerSessionRepository { get }
}

/// Conforms to `HistoryCellDependency` so it can seed the rows' component.
@MainActor
final class HistoryComponent: Component<HistoryDependency>, HistoryCellDependency {
    let fingers: FingerHomeViewModel
    let sessions: any SessionRepository
    let fingerReplayRepository: any FingerSessionRepository
    /// One router for the tab's single stack.
    let router = HistoryRouter()
    /// Created once: it wires the router's hooks to its path, so a rebuilt root must not
    /// replace it.
    lazy var reportsViewModel = ReportsViewModel(
        home: fingers,
        armReports: TaskReportsViewModel(repository: sessions),
        router: router
    )

    lazy var cellBuilder = HistoryCellBuilder(
        component: HistoryCellComponent(dependency: self)
    )

    init(dependency: HistoryDependency) {
        self.fingers = dependency.fingers
        self.sessions = dependency.sessions
        self.fingerReplayRepository = dependency.fingerReplayRepository
        super.init(with: dependency)
    }
}
