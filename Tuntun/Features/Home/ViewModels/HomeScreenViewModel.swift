//
//  HomeScreenViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

@MainActor
protocol HomeViewModelProtocol: AnyObject, Observable {
    var path: [HomeRoute] { get set }
    var sheet: HomeSheet? { get set }
    var cover: PlanCover? { get set }
    var rows: [DailyPlanRow] { get }
    var errorKey: String? { get }
    var isFinishedToday: Bool { get }
    /// Some of today's plan is done, or a finger session was saved for later.
    var hasProgress: Bool { get }

    func refresh() async
    func openPracticePreferences()
    /// Starts today's plan at the first undone item, or at `itemID` when a card was tapped.
    func begin(from itemID: String?)
}

/// Beranda: exposes `HomeRouter`'s navigation stack, sheet and the full-screen cover that runs
/// today's plan.
@MainActor
@Observable
final class HomeScreenViewModel: HomeViewModelProtocol {
    private let fingers: FingerHomeViewModel
    private let plan: DailyPlanViewModel
    @ObservationIgnored private let armRoutine: RoutineViewModel
    @ObservationIgnored private let taskRoutine: RoutineViewModel
    @ObservationIgnored private let router: HomeRouter

    init(
        fingers: FingerHomeViewModel,
        armRoutine: RoutineViewModel,
        taskRoutine: RoutineViewModel,
        plan: DailyPlanViewModel,
        router: HomeRouter
    ) {
        self.fingers = fingers
        self.armRoutine = armRoutine
        self.taskRoutine = taskRoutine
        self.plan = plan
        self.router = router
    }

    // MARK: - Navigation state

    // Owned by the router, so the plan and session pages change it through their protocols.

    var path: [HomeRoute] {
        get {
            router.path
        }
        set {
            router.path = newValue
        }
    }

    var sheet: HomeSheet? {
        get {
            router.sheet
        }
        set {
            router.sheet = newValue
        }
    }

    var cover: PlanCover? {
        get {
            router.cover
        }
        set {
            router.cover = newValue
        }
    }

    // MARK: - Plan

    var rows: [DailyPlanRow] {
        plan.rows()
    }

    var errorKey: String? {
        plan.errorKey
    }

    var isFinishedToday: Bool {
        plan.isFinishedToday
    }

    var hasProgress: Bool {
        plan.completedCount > 0 || fingers.checkpoint != nil
    }

    func refresh() async {
        await fingers.refresh()
        await armRoutine.load()
        await taskRoutine.load()
        await plan.load()
    }

    func openPracticePreferences() {
        router.openPracticePreferences()
    }

    func begin(from itemID: String?) {
        plan.begin(from: itemID)
    }
}
