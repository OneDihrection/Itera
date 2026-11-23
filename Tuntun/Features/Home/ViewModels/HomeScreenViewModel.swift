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
    var panel: HomePanel? { get set }
    var cover: PlanCover? { get set }
    var rows: [DailyPlanRow] { get }
    var errorKey: String? { get }
    var isFinishedToday: Bool { get }
    var completedCount: Int { get }
    /// Some of today's plan is done, or a finger session was saved for later.
    var hasProgress: Bool { get }
    var selectedDate: Date { get }
    var visibleWeek: [Date] { get }
    var selectedDayState: HomeDayState { get }
    /// Exercise IDs completed on the selected historical date.
    var selectedCompletedItemIDs: Set<String> { get }

    func refresh() async
    func openPracticePreferences()
    func selectDate(_ date: Date)
    func moveVisibleWeek(by offset: Int)
    func synchronizeCalendarDay()
    func returnToToday()
    /// Starts today's plan at the first undone item, or at `itemID` when a card was tapped.
    func begin(from itemID: String?)
}

/// Beranda: exposes `HomeRouter`'s navigation stack, Preferences panel and the full-screen cover that runs
/// today's plan.
@MainActor
@Observable
final class HomeScreenViewModel: HomeViewModelProtocol {
    private let fingers: FingerHomeViewModel
    private let plan: DailyPlanViewModel
    @ObservationIgnored private let armRoutine: RoutineViewModel
    @ObservationIgnored private let taskRoutine: RoutineViewModel
    @ObservationIgnored private let progressRepository: any DailyPlanProgressRepository
    @ObservationIgnored private let router: HomeRouter
    private var historicalProgress: [DailyPlanProgress]?
    private(set) var selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    private var visibleWeekAnchor = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    private var referenceToday = Calendar.autoupdatingCurrent.startOfDay(for: .now)

    init(
        fingers: FingerHomeViewModel,
        armRoutine: RoutineViewModel,
        taskRoutine: RoutineViewModel,
        plan: DailyPlanViewModel,
        progressRepository: any DailyPlanProgressRepository,
        router: HomeRouter
    ) {
        self.fingers = fingers
        self.armRoutine = armRoutine
        self.taskRoutine = taskRoutine
        self.plan = plan
        self.progressRepository = progressRepository
        self.router = router
    }

    // MARK: - Navigation state

    // Owned by the router, so the plan and session pages change it through their protocols.

    var path: [HomeRoute] {
        get {
            router.path
        }
        set {
            let leavesIntro = router.path.contains(where: \.isPlanIntro)
                && !newValue.contains(where: \.isPlanIntro)

            router.path = newValue

            // The intro's system back button pops the stack itself, so the plan that intro
            // started ends here, as the former custom back button's `plan.end()` did. The plan's
            // own `end()` stops running first, so this never ends it twice.
            if leavesIntro, plan.isRunning {
                plan.end()
            }
        }
    }

    var panel: HomePanel? {
        get {
            router.panel
        }
        set {
            router.panel = newValue
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

    var completedCount: Int {
        plan.completedCount
    }

    var hasProgress: Bool {
        plan.completedCount > 0 || fingers.checkpoint != nil
    }

    var visibleWeek: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let anchor = calendar.startOfDay(for: visibleWeekAnchor)
        let weekday = calendar.component(.weekday, from: anchor)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: anchor) ?? anchor

        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monday)
        }
    }

    var selectedDayState: HomeDayState {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let selected = calendar.startOfDay(for: selectedDate)
        let offset = calendar.dateComponents([.day], from: today, to: selected).day ?? 0

        switch offset {
        case ..<0:
            guard historicalProgress != nil else {
                return .completed
            }

            guard let progress = historicalProgress(on: selected) else {
                return .missed
            }

            let plannedItemIDs = progress.planned.isEmpty
                ? Set(rows.map(\.id))
                : Set(progress.planned)
            let completedItemIDs = progress.completed.intersection(plannedItemIDs)

            if completedItemIDs.isEmpty {
                return .missed
            }

            return plannedItemIDs.isSubset(of: completedItemIDs) ? .completed : .partial
        case 0:
            return plan.isFinishedToday ? .completed : .current
        case 1:
            return .upcoming
        default:
            return .noSchedule
        }
    }

    var selectedCompletedItemIDs: Set<String> {
        let visibleItemIDs = Set(rows.map(\.id))
        return historicalProgress(on: selectedDate)?.completed.intersection(visibleItemIDs) ?? []
    }

    func refresh() async {
        synchronizeCalendarDay()
        await fingers.refresh()
        await armRoutine.load()
        await taskRoutine.load()
        await plan.load()
        await loadHistoricalProgress()
    }

    func openPracticePreferences() {
        router.openPracticePreferences()
    }

    func selectDate(_ date: Date) {
        let date = Calendar.autoupdatingCurrent.startOfDay(for: date)
        selectedDate = date
        visibleWeekAnchor = date
    }

    func moveVisibleWeek(by offset: Int) {
        guard offset != 0,
              let movedDate = Calendar.autoupdatingCurrent.date(
                byAdding: .day,
                value: offset * 7,
                to: visibleWeekAnchor
              ) else {
            return
        }

        visibleWeekAnchor = movedDate
    }

    /// Keeps the relative Today/Tomorrow/Past states correct when the device crosses midnight
    /// or its date changes while the app is suspended.
    func synchronizeCalendarDay() {
        let calendar = Calendar.autoupdatingCurrent
        let newToday = calendar.startOfDay(for: .now)

        if calendar.isDate(selectedDate, inSameDayAs: referenceToday) {
            selectedDate = newToday
            visibleWeekAnchor = newToday
        }

        referenceToday = newToday
    }

    func returnToToday() {
        selectDate(.now)
    }

    func begin(from itemID: String?) {
        plan.begin(from: itemID)
    }

    private func loadHistoricalProgress() async {
        do {
            historicalProgress = try await progressRepository.history()
        } catch {
            // Keep the previous completed-day fallback when history cannot be read safely.
            historicalProgress = nil
        }
    }

    private func historicalProgress(on date: Date) -> DailyPlanProgress? {
        historicalProgress?.first {
            Calendar.autoupdatingCurrent.isDate($0.day, inSameDayAs: date)
        }
    }
}
