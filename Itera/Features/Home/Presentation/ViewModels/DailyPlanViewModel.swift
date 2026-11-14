//
//  DailyPlanViewModel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import Foundation
import Observation

/// One plan item as Beranda and the "Selanjutnya" page show it.
struct DailyPlanRow: Identifiable, Equatable {
    enum Status: Equatable {
        case done
        case next
        case upcoming
    }

    /// A value shown under the title; the view chooses the wording and icon.
    enum Detail: Equatable {
        case sets(Int)
        case repetitions(Int)
        case holdSeconds(Int)
    }

    let item: DailyPlanItem
    let titleKey: String
    let details: [Detail]
    let status: Status

    var id: String {
        item.id
    }
}

/// Runs today's plan: exercises from different programs, one after another.
///
/// The first item's intro validates readiness before opening its session.
/// Completed sessions advance through the rest and countdown before launching the next item.
/// Settings are read from each
/// program's own storage at launch, so the cards and the session always agree.
@MainActor
@Observable
final class DailyPlanViewModel {
    static let completionPreviewDuration: Duration = .seconds(4)
    /// The doctor's prescription in patient mode (ADR-008), otherwise the fixed plan.
    private(set) var items: [DailyPlanItem]
    /// Breaths of the rest after the item that just finished, from its prescription.
    private(set) var restBreaths = LongRestBreath.defaultCount
    private(set) var progress = DailyPlanProgress.empty(on: .now)
    /// Index of the item whose session is open, or that just finished.
    private(set) var currentIndex: Int?
    private(set) var isRunning = false
    private(set) var restingBeforeNext = false
    private(set) var errorKey: String?
    var sidePreference = UserDefaults.standard.string(forKey: PracticePreferences.dailyPlanSide) ?? "" {
        didSet { UserDefaults.standard.set(sidePreference, forKey: PracticePreferences.dailyPlanSide) }
    }

    @ObservationIgnored private let repository: any DailyPlanProgressRepository
    @ObservationIgnored private var loadFailed = false
    /// A prescription that arrived while a plan ran; it applies when the run ends.
    @ObservationIgnored private var pendingItems: [DailyPlanItem]?

    init(items: [DailyPlanItem] = DailyPlan.standard, repository: any DailyPlanProgressRepository) {
        self.items = items
        self.repository = repository
    }

    // MARK: - Prescription

    /// Replaces the items with the prescription's, in the doctor's order. A running plan keeps
    /// its items until it ends, so an update never changes the exercise in progress.
    func apply(_ prescription: Prescription?) {
        let prescribed = (prescription?.items ?? []).compactMap { item in
            item.catalogItem.map { DailyPlanItem(exercise: $0.exercise, prescribed: item) }
        }

        guard prescribed != items else {
            return
        }

        if isRunning {
            pendingItems = prescribed
        } else {
            items = prescribed
        }
    }

    var hasItems: Bool {
        !items.isEmpty
    }

    // MARK: - Progress

    func load() async {
        do {
            let saved = try await repository.load()
            progress = (saved ?? .empty(on: .now)).current(on: .now)
            loadFailed = false
            errorKey = nil
        } catch {
            // Keep the file untouched; the plan still runs, but progress is not saved.
            loadFailed = true
            errorKey = "plan.progressUnavailable"
        }
    }

    var completedCount: Int {
        items.filter { progress.completed.contains($0.id) }.count
    }

    var isFinishedToday: Bool {
        !items.isEmpty && completedCount == items.count
    }

    /// The first item not yet done today, or `nil` when everything is done.
    var nextIndex: Int? {
        items.firstIndex { !progress.completed.contains($0.id) }
    }

    /// The item the "Selanjutnya" page offers: the next undone item after the current one.
    var upcomingIndex: Int? {
        let start = (currentIndex ?? -1) + 1

        guard start < items.count else {
            return nil
        }

        return items[start...].firstIndex { !progress.completed.contains($0.id) }
    }

    var hasAutomaticRest: Bool {
        isRunning && !restingBeforeNext && upcomingIndex != nil
    }

    var nextSessionItemID: String? {
        guard let currentIndex else {
            return nil
        }
        return items[currentIndex].id
    }

    var nextSessionTitleKey: String? {
        currentIndex.map { Self.titleKey(for: items[$0].exercise) }
    }

    // MARK: - Rows

    func rows(in dependencies: AppDependencies) -> [DailyPlanRow] {
        let next = nextIndex

        return items.indices.map { index in
            let item = items[index]

            let status: DailyPlanRow.Status
            if progress.completed.contains(item.id) {
                status = .done
            } else if index == next {
                status = .next
            } else {
                status = .upcoming
            }

            return DailyPlanRow(
                item: item,
                titleKey: Self.titleKey(for: item.exercise),
                details: details(for: item.exercise, in: dependencies),
                status: status
            )
        }
    }

    static func titleKey(for exercise: DailyPlanItem.Exercise) -> String {
        switch exercise {
        case .finger(let exercise):
            return exercise.title
        case .therapy(let kind):
            return "session." + kind.rawValue
        case .balance(let exercise):
            return exercise.key("title")
        }
    }

    private func details(
        for exercise: DailyPlanItem.Exercise,
        in dependencies: AppDependencies
    ) -> [DailyPlanRow.Detail] {
        if let prescribed = items.first(where: { $0.exercise == exercise })?.prescribed {
            return [.sets(prescribed.sets), .repetitions(prescribed.work)]
        }

        switch exercise {
        case .finger(let exercise):
            let routine = dependencies.homeModel(for: exercise.category).routine
            return [.sets(routine.sets), .repetitions(routine.repetitions)]

        case .therapy(let kind):
            let exercise = routineExercise(for: kind, in: dependencies)
            let goal = exercise.activities.first?.goal ?? 1
            return [.sets(exercise.sets), .repetitions(goal)]

        case .balance(let exercise):
            let settings = BalancePracticeSettings(exercise: exercise)

            return [.sets(settings.sets), .repetitions(settings.repetitions)]
        }
    }

    private var selectedSide: HandSide? {
        HandSide(rawValue: sidePreference)
    }

    private func prescribed(_ exercise: DailyPlanItem.Exercise) -> PrescriptionItem? {
        items.first { $0.exercise == exercise }?.prescribed
    }

    /// The doctor's side for one-sided items. "Both" has no single side here.
    private func prescribedSide(_ item: PrescriptionItem) -> HandSide? {
        switch item.side {
        case .left:
            return .left
        case .right:
            return .right
        case .both:
            return item.firstSide
        case nil:
            return nil
        }
    }

    func fingerSide(for exercise: FingerExercise, in dependencies: AppDependencies) -> HandSide {
        if let prescribed = prescribed(.finger(exercise)), let side = prescribedSide(prescribed) {
            return side
        }

        return selectedSide ?? dependencies.homeModel(for: exercise.category).routine.side
    }

    func balanceSettings(for exercise: BalanceExercise) -> BalancePracticeSettings {
        if let item = prescribed(.balance(exercise)) {
            let arm: BalanceArmSelection

            switch item.side {
            case .left:
                arm = .left
            case .right:
                arm = .right
            case .both, nil:
                arm = .both
            }

            return BalancePracticeSettings(
                repetitions: item.work,
                holdSeconds: item.holdSeconds ?? BalancePracticeSettings.defaultHoldSeconds,
                armSelection: arm,
                sets: item.sets,
                restSeconds: item.setRestSeconds
            )
        }

        var settings = BalancePracticeSettings(exercise: exercise)
        if !exercise.isSitToStand, let side = selectedSide {
            settings.armSelection = side == .left ? .left : .right
        }
        return settings
    }

    /// Applies the daily-plan side to the saved exercise configuration for this session.
    func routineExercise(for kind: TherapyKind, in dependencies: AppDependencies) -> RoutineExercise {
        if let item = prescribed(.therapy(kind)) {
            var exercise = RoutineExercise(kind: kind)

            switch item.side {
            case .left:
                exercise.sides = .left
            case .right:
                exercise.sides = .right
            case .both, nil:
                exercise.sides = .both
            }

            exercise.firstSide = item.firstSide == .left ? .left : .right
            exercise.leftGoal = item.work
            exercise.rightGoal = item.work
            exercise.rounds = item.work
            exercise.sets = item.sets
            return exercise
        }

        guard let category = kind.category else {
            return RoutineExercise(kind: kind)
        }

        let configuration = dependencies.routineModel(for: category).configuration
        var exercise = configuration.exercises.first { $0.kind == kind } ?? RoutineExercise(kind: kind)
        if let side = selectedSide {
            exercise.sides = side == .left ? .left : .right
        }
        return exercise
    }

    // MARK: - Running

    /// "Latihan N" of the exercise whose session is open, while the plan runs.
    var currentNumber: Int? {
        guard isRunning, let currentIndex else {
            return nil
        }

        return currentIndex + 1
    }

    /// Position of an item in the plan, shown as "Latihan N".
    func number(of itemID: String) -> Int {
        (items.firstIndex { $0.id == itemID } ?? 0) + 1
    }

    /// Opens the intro of the first undone item, or of `itemID` when a card was tapped.
    /// Nothing starts yet: the intro's own Start is the explicit start.
    func begin(from itemID: String? = nil, router: NavigationRouter) {
        let chosen = itemID.flatMap { id in items.firstIndex { $0.id == id } }

        guard let index = chosen ?? nextIndex ?? items.indices.first else {
            return
        }

        isRunning = true
        currentIndex = index
        router.push(.planIntro(items[index].id))
    }

    /// "Mulai Latihan" on an intro: validates permissions and listening once, as an explicit
    /// start requires, then opens that item's session.
    func startCurrent(
        readiness: HomeViewModel,
        dependencies: AppDependencies,
        router: NavigationRouter
    ) async {
        guard isRunning, let currentIndex else {
            return
        }

        guard await readiness.performAction() else {
            return
        }

        launch(currentIndex, dependencies: dependencies, router: router)
    }

    /// Called by a session's finishing action while the plan runs. Only a session that reached
    /// its goal counts as done. A completed item leads to rest, or to the day-complete page.
    func finish(completed: Bool, router: NavigationRouter) {
        guard isRunning, !restingBeforeNext, let currentIndex else {
            return
        }

        guard completed else {
            end(router: router)
            return
        }
        progress = progress.current(on: .now)
        progress.completed.insert(items[currentIndex].id)
        restBreaths = items[currentIndex].prescribed?.breathsBeforeNext ?? LongRestBreath.defaultCount
        Task { await saveProgress() }

        let next = upcomingIndex
        self.currentIndex = next
        restingBeforeNext = next != nil

        if router.presentedFullScreenCovers.isEmpty {
            router.presentFullScreenCover(.planNext)
        } else {
            router.replaceFullScreenCover(with: .planNext)
        }
    }

    func launchAfterRest(dependencies: AppDependencies, router: NavigationRouter) {
        guard isRunning, restingBeforeNext, let currentIndex else {
            return
        }
        restingBeforeNext = false
        launch(currentIndex, dependencies: dependencies, router: router, replacingRest: true)
    }

    /// "Kembali" on an intro, "Kembali ke Beranda" after the last item, or leaving a session
    /// without continuing.
    func end(router: NavigationRouter) {
        isRunning = false
        restingBeforeNext = false
        currentIndex = nil

        if let pendingItems {
            items = pendingItems
            self.pendingItems = nil
        }

        router.dismiss()
        router.popToRoot()
    }

    private func launch(
        _ index: Int, dependencies: AppDependencies, router: NavigationRouter,
        replacingRest: Bool = false
    ) {
        currentIndex = index
        let route: AppRoute

        switch items[index].exercise {
        case .finger(let exercise):
            let checkpoint = dependencies.homeModel(for: exercise.category).checkpoint
            let side = selectedSide
            let matchesSide = side.map { checkpoint?.routine.side == $0 } ?? true
            let prescribed = items[index].prescribed
            let prescribedSide = prescribed.flatMap(prescribedSide)
            let sessionSide = prescribedSide ?? side
            let matchesPrescription = prescribed.map {
                checkpoint?.routine.sets == $0.sets && checkpoint?.routine.repetitions == $0.work
            } ?? true
            dependencies.prepareSession(
                category: exercise.category,
                continuing: checkpoint?.routine.only == exercise
                    && (sessionSide.map { checkpoint?.routine.side == $0 } ?? matchesSide)
                    && matchesPrescription,
                only: exercise,
                side: sessionSide,
                prescribed: prescribed
            )
            route = .fingerSession

        case .therapy(let kind):
            let exercise = routineExercise(for: kind, in: dependencies)
            let configuration = kind.category.map { dependencies.routineModel(for: $0).configuration }
                ?? RoutineConfiguration()
            let rest = items[index].prescribed?.setRestSeconds ?? configuration.restSeconds
            dependencies.selectedRoutine = Routine(
                activities: exercise.activities,
                restSeconds: Double(rest),
                practiceSeconds: Double(configuration.practiceSeconds)
            )
            route = .therapySession

        case .balance(let exercise):
            let settings = balanceSettings(for: exercise)
            route = .balanceSession(exercise: exercise, settings: settings)
        }

        if replacingRest {
            router.replaceFullScreenCover(with: route)
        } else {
            router.presentFullScreenCover(route)
        }
    }

    private func saveProgress() async {
        guard !loadFailed else {
            return
        }

        do {
            try await repository.save(progress)
        } catch {
            errorKey = "plan.progressUnavailable"
        }
    }
}
