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

/// Beranda: owns its navigation stack, its sheet and the full-screen cover that runs today's
/// plan, and wires `HomeRouter` to them.
@MainActor
@Observable
final class HomeScreenViewModel: HomeViewModelProtocol {
    var path: [HomeRoute] = []
    var sheet: HomeSheet?
    var cover: PlanCover?

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

        wire(router)
    }

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

    // MARK: - Router hooks

    private func wire(_ router: HomeRouter) {
        router.presentSheet = { [weak self] sheet in
            self?.sheet = sheet
        }
        router.dismissPresentedSheet = { [weak self] in
            self?.sheet = nil
        }
        router.pushIntro = { [weak self] itemID in
            self?.path.append(.planIntro(itemID))
        }
        router.returnHome = { [weak self] in
            self?.sheet = nil
            self?.path.removeAll()
        }
        router.presentPlanCover = { [weak self] route in
            self?.cover = PlanCover(route: route)
        }
        router.replacePlanCover = { [weak self] route in
            self?.replaceCover(with: route)
        }
        router.dismissPlanCover = { [weak self] in
            self?.cover = nil
        }
        router.coverPresented = { [weak self] in
            self?.cover != nil
        }
    }

    /// Keeps the cover's identity so it stays mounted and only its page changes.
    private func replaceCover(with route: PlanCoverRoute) {
        guard cover != nil else {
            cover = PlanCover(route: route)
            return
        }

        cover?.route = route
    }
}
