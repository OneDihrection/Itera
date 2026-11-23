//
//  FingerSessionCompleteViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

@MainActor
protocol FingerSessionCompleteViewModelProtocol: AnyObject, Observable {
    var summary: FingerSessionSummary? { get }
    var exerciseTitle: String { get }
    var sessionLanguage: AppLanguage { get }
    /// The item's position in today's plan while the plan runs.
    var exerciseNumber: Int? { get }
    var isPlanRunning: Bool { get }
    var completed: Bool { get }
    /// A completed session moves on to the plan's rest by itself.
    var automaticallyRests: Bool { get }
    /// Saving has ended, successfully or not, so the way on can appear.
    var savingFinished: Bool { get }

    func save() async
    /// Leads on to the next exercise while the plan runs, otherwise to Progress.
    func close()
}

/// The finger exercises' all-done page: saves the finished session, then hands back to the plan.
@MainActor
@Observable
final class FingerSessionCompleteViewModel: FingerSessionCompleteViewModelProtocol {
    private(set) var savingFinished = false

    private let fingerSessionService: FingerSessionService
    @ObservationIgnored private let plan: any DailyPlanSessionReporting
    /// Refreshed after saving so Beranda and Progress show the new session.
    @ObservationIgnored private let home: FingerHomeViewModel
    @ObservationIgnored private let tabs: any TabRouterProtocol
    @ObservationIgnored private let router: any SessionRouterProtocol

    init(
        fingerSessionService: FingerSessionService,
        plan: any DailyPlanSessionReporting,
        home: FingerHomeViewModel,
        tabs: any TabRouterProtocol,
        router: any SessionRouterProtocol
    ) {
        self.fingerSessionService = fingerSessionService
        self.plan = plan
        self.home = home
        self.tabs = tabs
        self.router = router
    }

    var summary: FingerSessionSummary? {
        fingerSessionService.session?.finalSummary
    }

    var exerciseTitle: String {
        fingerSessionService.session?.exerciseTitle ?? ""
    }

    var sessionLanguage: AppLanguage {
        fingerSessionService.session?.sessionLanguage ?? AppLanguage.selected
    }

    var exerciseNumber: Int? {
        plan.currentNumber
    }

    var isPlanRunning: Bool {
        plan.isRunning
    }

    var completed: Bool {
        summary?.outcome == .completed
    }

    var automaticallyRests: Bool {
        completed && plan.hasAutomaticRest
    }

    func save() async {
        await fingerSessionService.session?.saveFinalSummary()

        // Leaving waits only for the summary itself, not for the history list to reload.
        savingFinished = true

        if fingerSessionService.session?.finalSummarySaved == true {
            await home.refresh()
        }
    }

    func close() {
        guard !plan.isRunning else {
            plan.finish(completed: completed)
            return
        }

        router.closeSession()
        tabs.showProgress()
    }
}
