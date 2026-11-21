//
//  ReportsViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

@MainActor
protocol ReportsViewModelProtocol: AnyObject, Observable {
    var path: [HistoryRoute] { get set }
    /// Practice per day, joined from every saved session and the plan's saved days.
    var practiceHistory: PracticeHistory { get }
    /// Any date inside the month the calendar shows.
    var displayedMonth: Date { get }
    var today: Date { get }
    var canShowNextMonth: Bool { get }
    var errorKey: String? { get }

    func refresh() async
    func showPreviousMonth()
    func showNextMonth()
    /// Opens one day's progress page.
    func openDay(_ day: Date)
}

/// The Progress tab: exposes its router's navigation stack, joins finger, guided and plan
/// history into one calendar, and opens a day's progress page through the router.
@MainActor
@Observable
final class ReportsViewModel: ReportsViewModelProtocol {
    private(set) var practiceHistory = PracticeHistory.empty
    private(set) var displayedMonth = Date.now
    private(set) var today = Date.now
    private var planErrorKey: String?

    @ObservationIgnored private let home: FingerHomeViewModel
    @ObservationIgnored private let router: HistoryRouter
    @ObservationIgnored private let planHistoryRepository: any DailyPlanHistoryRepository
    @ObservationIgnored private let calendar = Calendar.current
    private let armReports: TaskReportsViewModel

    init(
        home: FingerHomeViewModel,
        armReports: TaskReportsViewModel,
        planHistoryRepository: any DailyPlanHistoryRepository,
        router: HistoryRouter
    ) {
        self.home = home
        self.router = router
        self.armReports = armReports
        self.planHistoryRepository = planHistoryRepository
    }

    /// The stack path lives in the router, so pushes from rows and pages land on this stack.
    var path: [HistoryRoute] {
        get {
            router.path
        }
        set {
            router.path = newValue
        }
    }

    var errorKey: String? {
        home.errorKey ?? armReports.errorKey ?? planErrorKey
    }

    /// The calendar never moves past the current month.
    var canShowNextMonth: Bool {
        !calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
    }

    // MARK: - Loading

    func refresh() async {
        today = .now

        await home.refresh()
        await armReports.load()

        let planDays: [DailyPlanDay]

        do {
            planDays = try await planHistoryRepository.planHistory()
            planErrorKey = nil
        } catch {
            // The calendar still shows sessions; only fully completed days are unknown.
            planDays = []
            planErrorKey = "progress.planHistoryUnavailable"
        }

        practiceHistory = PracticeHistory(
            fingerSessions: home.history,
            sessions: armReports.summaries,
            planDays: planDays,
            calendar: calendar
        )
    }

    // MARK: - Calendar

    func showPreviousMonth() {
        moveMonth(by: -1)
    }

    func showNextMonth() {
        guard canShowNextMonth else {
            return
        }

        moveMonth(by: 1)
    }

    private func moveMonth(by months: Int) {
        guard let month = calendar.date(byAdding: .month, value: months, to: displayedMonth) else {
            return
        }

        displayedMonth = month
    }

    // MARK: - Navigation

    func openDay(_ day: Date) {
        let start = calendar.startOfDay(for: day)

        guard start <= calendar.startOfDay(for: today) else {
            return
        }

        router.showPracticeDay(start)
    }
}
