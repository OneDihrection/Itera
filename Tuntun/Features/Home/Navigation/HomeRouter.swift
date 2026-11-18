//
//  HomeRouter.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

// MARK: - Routes

/// A page pushed onto Beranda's stack.
enum HomeRoute: Hashable {
    /// The intro page of one daily-plan item, by item id.
    case planIntro(String)
}

/// A sheet presented over Beranda.
enum HomeSheet: String, Identifiable {
    case practicePreferences

    var id: Self {
        self
    }
}

/// A page in the full-screen cover that runs today's plan. The cover stays mounted while its
/// route changes, so sessions, rest and the next intro hand over without a dismissal.
enum PlanCoverRoute: Hashable {
    /// One guided session running this routine snapshot.
    case therapySession(Routine)
    case balanceSession(exercise: BalanceExercise, settings: BalancePracticeSettings)
    case fingerSession
    case fingerSessionComplete
    /// The rest between daily-plan exercises, or the page after the last one.
    case planNext
}

/// The presented cover. Its identity survives route replacement.
struct PlanCover: Identifiable {
    let id: UUID
    var route: PlanCoverRoute

    init(id: UUID = UUID(), route: PlanCoverRoute) {
        self.id = id
        self.route = route
    }
}

// MARK: - Router protocols

/// Beranda's own navigation.
@MainActor
protocol HomeRouterProtocol: AnyObject {
    func openPracticePreferences()
    func dismissSheet()
}

/// The navigation today's plan drives while it runs.
@MainActor
protocol DailyPlanRouterProtocol: AnyObject {
    var isCoverPresented: Bool { get }

    func showIntro(itemID: String)
    func presentCover(_ route: PlanCoverRoute)
    /// Changes the visible cover's page in place; presents one when none is visible.
    func replaceCover(with route: PlanCoverRoute)
    /// Dismisses the cover and returns to Beranda's root.
    func endRun()
}

/// What a session page inside the plan cover may do on its own.
@MainActor
protocol SessionRouterProtocol: AnyObject {
    func showFingerSessionComplete()
    func closeSession()
}

// MARK: - Router

/// Beranda's router: owns its stack path, its settings sheet and the full-screen cover the
/// plan's sessions, rest and next intro share. Beranda's screen model forwards this state to its
/// view; the settings page, the plan and the session pages each receive this router through their
/// initializers as their own narrow protocol.
@MainActor
@Observable
final class HomeRouter: HomeRouterProtocol, DailyPlanRouterProtocol, SessionRouterProtocol {
    var path: [HomeRoute] = []
    var sheet: HomeSheet?
    var cover: PlanCover?

    var isCoverPresented: Bool {
        cover != nil
    }

    func openPracticePreferences() {
        sheet = .practicePreferences
    }

    func dismissSheet() {
        sheet = nil
    }

    func showIntro(itemID: String) {
        path.append(.planIntro(itemID))
    }

    func presentCover(_ route: PlanCoverRoute) {
        cover = PlanCover(route: route)
    }

    /// Keeps the cover's identity so it stays mounted and only its page changes.
    func replaceCover(with route: PlanCoverRoute) {
        guard cover != nil else {
            cover = PlanCover(route: route)
            return
        }

        cover?.route = route
    }

    func endRun() {
        cover = nil
        sheet = nil
        path.removeAll()
    }

    func showFingerSessionComplete() {
        replaceCover(with: .fingerSessionComplete)
    }

    func closeSession() {
        cover = nil
    }
}
