//
//  HomeRouter.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

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

// MARK: - Routers

/// Beranda's own router: its settings sheet. The plan's pages use `PlanRouter`.
@MainActor
final class HomeRouter: HomeRouterProtocol {
    var presentSheet: ((HomeSheet) -> Void)?
    var dismissPresentedSheet: (() -> Void)?

    func openPracticePreferences() {
        presentSheet?(.practicePreferences)
    }

    func dismissSheet() {
        dismissPresentedSheet?()
    }
}

/// The plan's router: the intro pushed on Beranda's stack and the full-screen cover its
/// sessions, rest and next intro share. Beranda's screen model owns that state and wires these
/// hooks; the plan and the session pages receive this router through their initializers.
@MainActor
final class PlanRouter: DailyPlanRouterProtocol, SessionRouterProtocol {
    var pushIntro: ((String) -> Void)?
    var returnHome: (() -> Void)?
    var presentPlanCover: ((PlanCoverRoute) -> Void)?
    var replacePlanCover: ((PlanCoverRoute) -> Void)?
    var dismissPlanCover: (() -> Void)?
    var coverPresented: (() -> Bool)?

    var isCoverPresented: Bool {
        coverPresented?() ?? false
    }

    func showIntro(itemID: String) {
        pushIntro?(itemID)
    }

    func presentCover(_ route: PlanCoverRoute) {
        presentPlanCover?(route)
    }

    func replaceCover(with route: PlanCoverRoute) {
        replacePlanCover?(route)
    }

    func endRun() {
        dismissPlanCover?()
        returnHome?()
    }

    func showFingerSessionComplete() {
        replacePlanCover?(.fingerSessionComplete)
    }

    func closeSession() {
        dismissPlanCover?()
    }
}
