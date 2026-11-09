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
/// Each session keeps its own flow. While a plan is running, a session's finishing action
/// calls `finish(completed:router:)` instead of its usual exit, and this model shows the
/// "Selanjutnya" page before starting the next item. Settings are read from each program's
/// own storage at launch, so the cards and the session always agree.
@MainActor
@Observable
final class DailyPlanViewModel {
    let items: [DailyPlanItem]
    private(set) var progress = DailyPlanProgress.empty(on: .now)
    /// Index of the item whose session is open, or that just finished.
    private(set) var currentIndex: Int?
    private(set) var isRunning = false
    private(set) var errorKey: String?

    @ObservationIgnored private let repository: any DailyPlanProgressRepository
    @ObservationIgnored private var loadFailed = false

    /// Time for the previous session's `onDisappear` cleanup to release the shared camera and
    /// audio before the next session's `.task` starts them again.
    private static let handoverDelay = Duration.milliseconds(500)

    init(items: [DailyPlanItem] = DailyPlan.standard, repository: any DailyPlanProgressRepository) {
        self.items = items
        self.repository = repository
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
        completedCount == items.count
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

    private static func titleKey(for exercise: DailyPlanItem.Exercise) -> String {
        switch exercise {
        case .finger(.fingers):
            // `plan.fingerTitle` carries a deliberate line break for its own page.
            return "home.program.finger"
        case .finger(let category):
            return category.title
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
        switch exercise {
        case .finger(let category):
            let routine = dependencies.homeModel(for: category).routine
            return [.sets(routine.sets), .repetitions(routine.repetitions)]

        case .therapy(let kind):
            let exercise = Self.routineExercise(for: kind, in: dependencies)
            let goal = exercise.activities.first?.goal ?? 1
            return [.sets(exercise.sets), .repetitions(goal)]

        case .balance(let exercise):
            let settings = BalancePracticeSettings(exercise: exercise)

            guard !exercise.isSitToStand else {
                return [.repetitions(settings.repetitions)]
            }

            return [.repetitions(settings.repetitions), .holdSeconds(settings.holdSeconds)]
        }
    }

    /// The caregiver's saved settings for this activity kind, or the kind's defaults.
    private static func routineExercise(for kind: TherapyKind, in dependencies: AppDependencies) -> RoutineExercise {
        guard let category = kind.category else {
            return RoutineExercise(kind: kind)
        }

        let configuration = dependencies.routineModel(for: category).configuration
        return configuration.exercises.first { $0.kind == kind } ?? RoutineExercise(kind: kind)
    }

    // MARK: - Running

    /// Validates readiness once (permissions and listening, as an explicit Start requires),
    /// then opens the first undone item, or `itemID` when the caregiver tapped a card.
    func start(
        from itemID: String? = nil,
        readiness: HomeViewModel,
        dependencies: AppDependencies,
        router: NavigationRouter
    ) async {
        guard await readiness.performAction() else {
            return
        }

        let chosen = itemID.flatMap { id in items.firstIndex { $0.id == id } }

        guard let index = chosen ?? nextIndex ?? items.indices.first else {
            return
        }

        isRunning = true
        launch(index, dependencies: dependencies, router: router)
    }

    /// Called by a session's finishing action while the plan runs. Only a session that reached
    /// its goal counts as done; a stopped one stays open for later.
    func finish(completed: Bool, router: NavigationRouter) {
        guard isRunning, let currentIndex else {
            return
        }

        if completed {
            progress = progress.current(on: .now)
            progress.completed.insert(items[currentIndex].id)
            Task { await saveProgress() }
        }

        router.dismiss()
        router.popToRoot()
        router.presentFullScreenCover(.planNext)
    }

    /// "Lanjut" on the Selanjutnya page.
    func continueToNext(dependencies: AppDependencies, router: NavigationRouter) async {
        guard let index = upcomingIndex else {
            end(router: router)
            return
        }

        router.dismissFullScreenCover()
        try? await Task.sleep(for: Self.handoverDelay)

        guard isRunning else {
            return
        }

        launch(index, dependencies: dependencies, router: router)
    }

    /// "Selesai untuk hari ini", or leaving a session without continuing.
    func end(router: NavigationRouter) {
        isRunning = false
        currentIndex = nil
        router.dismiss()
        router.popToRoot()
    }

    private func launch(_ index: Int, dependencies: AppDependencies, router: NavigationRouter) {
        currentIndex = index

        switch items[index].exercise {
        case .finger(let category):
            let continuing = dependencies.homeModel(for: category).checkpoint != nil
            dependencies.prepareSession(category: category, continuing: continuing)
            router.presentFullScreenCover(.fingerSession)

        case .therapy(let kind):
            let exercise = Self.routineExercise(for: kind, in: dependencies)
            let configuration = kind.category.map { dependencies.routineModel(for: $0).configuration }
                ?? RoutineConfiguration()
            dependencies.selectedRoutine = Routine(
                activities: exercise.activities,
                restSeconds: Double(configuration.restSeconds),
                practiceSeconds: Double(configuration.practiceSeconds)
            )
            router.push(.therapySession)

        case .balance(let exercise):
            let settings = BalancePracticeSettings(exercise: exercise)
            router.push(.balanceSession(
                exercise: exercise,
                repetitions: settings.repetitions,
                holdSeconds: settings.holdSeconds,
                armSelection: settings.armSelection
            ))
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
