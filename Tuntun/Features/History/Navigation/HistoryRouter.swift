//
//  HistoryRouter.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

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

/// Navigation for the Progress tab. The reports list owns the stack and wires these hooks to its
/// path; every page on that stack receives this router.
@MainActor
final class HistoryRouter: HistoryRouterProtocol {
    var push: ((HistoryRoute) -> Void)?
    var popLast: (() -> Void)?
    var reset: (() -> Void)?

    func showFingerReport(id: UUID) {
        push?(.fingerReport(id))
    }

    func showSessionReport(id: UUID) {
        push?(.sessionReport(id))
    }

    func pop() {
        popLast?()
    }

    func popToRoot() {
        reset?()
    }
}
