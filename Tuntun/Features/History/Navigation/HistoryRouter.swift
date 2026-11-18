//
//  HistoryRouter.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

/// A page pushed onto the Progress tab's stack.
enum HistoryRoute: Hashable {
    case fingerReport(UUID)
    /// One arm-practice session with its key-repetition replays.
    case sessionReport(UUID)
}

@MainActor
protocol HistoryRouterProtocol: AnyObject {
    func showFingerReport(id: UUID)
    func showSessionReport(id: UUID)
    func pop()
    func popToRoot()
}

/// Navigation for the Progress tab. It owns the tab's stack path; the reports list binds its
/// `NavigationStack` to it, and every page on that stack receives this router.
@MainActor
@Observable
final class HistoryRouter: HistoryRouterProtocol {
    var path: [HistoryRoute] = []

    func showFingerReport(id: UUID) {
        path.append(.fingerReport(id))
    }

    func showSessionReport(id: UUID) {
        path.append(.sessionReport(id))
    }

    func pop() {
        guard !path.isEmpty else {
            return
        }

        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }
}
