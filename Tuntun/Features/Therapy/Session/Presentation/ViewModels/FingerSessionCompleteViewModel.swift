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
    var sessionLocale: Locale { get }
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

    private let launcher: FingerSessionLauncher
    @ObservationIgnored private let plan: any DailyPlanSessionReporting
    /// Refreshed after saving so Beranda and Progress show the new session.
    @ObservationIgnored private let home: FingerHomeViewModel
    @ObservationIgnored private let tabs: any TabRouterProtocol
    @ObservationIgnored private let router: any SessionRouterProtocol

    init(
        launcher: FingerSessionLauncher,
        plan: any DailyPlanSessionReporting,
        home: FingerHomeViewModel,
        tabs: any TabRouterProtocol,
        router: any SessionRouterProtocol
    ) {
        self.launcher = launcher
        self.plan = plan
        self.home = home
        self.tabs = tabs
        self.router = router
    }

    var summary: FingerSessionSummary? {
        launcher.session?.finalSummary
    }

    var exerciseTitle: String {
        launcher.session?.exerciseTitle ?? ""
    }

    var sessionLocale: Locale {
        launcher.session?.sessionLanguage.locale ?? AppLanguage.selected.locale
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
        await launcher.session?.saveFinalSummary()

        if launcher.session?.finalSummarySaved == true {
            await home.refresh()
        }

        savingFinished = true
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
