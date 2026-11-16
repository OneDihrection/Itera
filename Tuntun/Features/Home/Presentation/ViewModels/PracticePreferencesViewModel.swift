//
//  PracticePreferencesViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

@MainActor
protocol PracticePreferencesViewModelProtocol: AnyObject, Observable {
    /// The daily plan's training side: empty for the default, otherwise a `HandSide` raw value.
    var sidePreference: String { get set }
    var sets: Int { get set }
    var repetitions: Int { get set }
    var restSeconds: Int { get set }
    var errorKey: String? { get }

    /// Saves the finger routine and closes the sheet when saving succeeded.
    func done() async
    func save() async
}

/// The settings sheet: edits the same saved finger routine and plan side that Beranda uses.
/// A session in progress keeps the snapshot it started with.
@MainActor
@Observable
final class PracticePreferencesViewModel: PracticePreferencesViewModelProtocol {
    private let home: FingerHomeViewModel
    private let plan: DailyPlanViewModel
    @ObservationIgnored private let router: any HomeRouterProtocol

    init(
        home: FingerHomeViewModel,
        plan: DailyPlanViewModel,
        router: any HomeRouterProtocol
    ) {
        self.home = home
        self.plan = plan
        self.router = router
    }

    var sidePreference: String {
        get { plan.sidePreference }
        set { plan.sidePreference = newValue }
    }

    var sets: Int {
        get { home.routine.sets }
        set { home.routine.sets = newValue }
    }

    var repetitions: Int {
        get { home.routine.repetitions }
        set { home.routine.repetitions = newValue }
    }

    var restSeconds: Int {
        get { home.routine.restSeconds }
        set { home.routine.restSeconds = newValue }
    }

    var errorKey: String? {
        home.errorKey
    }

    func done() async {
        guard await home.saveRoutine() else {
            return
        }

        router.dismissSheet()
    }

    func save() async {
        _ = await home.saveRoutine()
    }
}
