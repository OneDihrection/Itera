//
//  DailyPlanViewModel.swift
//  Tuntun
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
final class DailyPlanViewModel: DailyPlanSessionReporting {
    /// The exercises Beranda shows, in order. Always `standardItems` in Release builds.
    private(set) var items: [DailyPlanItem]
    /// Every exercise the plan knows, in standard order.
    let standardItems: [DailyPlanItem]
    private(set) var progress = DailyPlanProgress.empty(on: .now)
    /// Index of the item whose session is open, or that just finished.
    private(set) var currentIndex: Int?
    private(set) var isRunning = false
    private(set) var restingBeforeNext = false
    private(set) var oppositionRestSide: HandSide?
    private(set) var armRaiseRestSide: TherapySide?
    /// The second arm of a scripted arm raise, waiting behind its long rest. `nil` starts at
    /// the first arm. The plan item is marked done only after its last arm.
    private var pendingArmRaiseSide: TherapySide?

    var usesScriptedLongRest: Bool {
        oppositionRestSide != nil || armRaiseRestSide != nil
    }
    private(set) var errorKey: String?
    var sidePreference = UserDefaults.standard.string(forKey: PracticePreferences.dailyPlanSide) ?? "" {
        didSet { UserDefaults.standard.set(sidePreference, forKey: PracticePreferences.dailyPlanSide) }
    }

    @ObservationIgnored private let repository: any DailyPlanProgressRepository
    @ObservationIgnored private let fingers: FingerHomeViewModel
    @ObservationIgnored private let forearm: FingerHomeViewModel
    @ObservationIgnored private let armRoutine: RoutineViewModel
    @ObservationIgnored private let taskRoutine: RoutineViewModel
    @ObservationIgnored private let fingerSessionService: FingerSessionService
    @ObservationIgnored private let router: any DailyPlanRouterProtocol
    @ObservationIgnored private var loadFailed = false

    #if DEBUG
    /// The debug plan editor's arrangement and custom counts.
    private(set) var debugLayout: DebugPlanLayout
    #endif

    /// - Parameters:
    ///   - fingers: the finger program, whose saved routine and checkpoint finger items use.
    ///   - forearm: the forearm program, used the same way for forearm items.
    ///   - armRoutine: the arm program's saved configuration for arm therapy items.
    ///   - taskRoutine: the task-oriented program's saved configuration.
    ///   - fingerSessions: prepares the finger session a finger item opens.
    ///   - router: opens intros and runs the plan's full-screen cover.
    init(
        items: [DailyPlanItem] = DailyPlan.standard,
        repository: any DailyPlanProgressRepository,
        fingers: FingerHomeViewModel,
        forearm: FingerHomeViewModel,
        armRoutine: RoutineViewModel,
        taskRoutine: RoutineViewModel,
        fingerSessionService: FingerSessionService,
        router: any DailyPlanRouterProtocol
    ) {
        self.standardItems = items
        self.repository = repository
        self.fingers = fingers
        self.forearm = forearm
        self.armRoutine = armRoutine
        self.taskRoutine = taskRoutine
        self.fingerSessionService = fingerSessionService
        self.router = router

        #if DEBUG
        let layout = DebugPlanLayout.load(for: items)
        self.debugLayout = layout
        self.items = layout.items(from: items)
        #else
        self.items = items
        #endif
    }

    #if DEBUG
    // MARK: - Debug layout

    /// Saves the debug editor's layout and rearranges Beranda. Ignored while a plan runs, so
    /// the open item's index never shifts under it.
    func applyDebugLayout(_ layout: DebugPlanLayout) {
        guard !isRunning else {
            return
        }

        let reconciled = layout.reconciled(with: standardItems)
        reconciled.save()
        debugLayout = reconciled
        items = reconciled.items(from: standardItems)
    }

    /// The sets and repetitions `item` runs with now, custom counts included. The editor
    /// starts a newly customized item from these.
    func debugCounts(
        for item: DailyPlanItem
    ) -> (sets: Int, repetitions: Int) {
        var sets = 1
        var repetitions = 1

        for detail in details(for: item.exercise) {
            switch detail {
            case .sets(let value):
                sets = value
            case .repetitions(let value):
                repetitions = value
            case .holdSeconds:
                break
            }
        }

        return (sets, repetitions)
    }
    #endif

    /// Custom counts from the debug plan editor; always `nil` in Release builds.
    private func customCounts(for itemID: String) -> (sets: Int?, repetitions: Int?)? {
        #if DEBUG
        return debugLayout.override(for: itemID).map { ($0.sets, $0.repetitions) }
        #else
        return nil
        #endif
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

    var hasAutomaticRest: Bool {
        isRunning && !restingBeforeNext && (upcomingIndex != nil || awaitsSecondArmRaiseSide)
    }

    /// The open arm raise still has its other arm to run after the long rest.
    private var awaitsSecondArmRaiseSide: Bool {
        guard let currentIndex,
              case .therapy(.armRaise) = items[currentIndex].exercise,
              let side = armRaiseScriptSide else {
            return false
        }

        return armRaiseSide(after: side) != nil
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

    func rows() -> [DailyPlanRow] {
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
                details: details(for: item.exercise),
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
        for exercise: DailyPlanItem.Exercise
    ) -> [DailyPlanRow.Detail] {
        switch exercise {
        case .finger(let exercise):
            let routine = fingerRoutine(for: exercise)
            return [.sets(routine.sets), .repetitions(routine.repetitions)]

        case .therapy(let kind):
            let exercise = routineExercise(for: kind)
            let goal = exercise.activities.first?.goal ?? 1
            return [.sets(exercise.sets), .repetitions(goal)]

        case .balance(let exercise):
            let settings = balanceSettings(for: exercise)

            return [.sets(settings.sets), .repetitions(settings.repetitions)]
        }
    }

    private var selectedSide: HandSide? {
        HandSide(rawValue: sidePreference)
    }

    func fingerSide(for exercise: FingerExercise) -> HandSide {
        selectedSide ?? homeModel(for: exercise.category).routine.side
    }

    func usesOppositionScript(itemID: String) -> Bool {
        guard AppLanguage.selected == .indonesian,
              let item = items.first(where: { $0.id == itemID }),
              case .finger(let exercise) = item.exercise else {
            return false
        }
        return OppositionGuidance.applies(to: exercise)
    }

    /// The opposition intro for this plan's side and counts; it names goals only when they
    /// match the recording.
    func oppositionIntroductionKeys() -> [String] {
        OppositionGuidance.introductionKeys(
            for: fingerSide(for: .opposition),
            routine: fingerRoutine(for: .opposition)
        )
    }

    /// The category's saved finger routine with this exercise's custom counts, if any.
    private func fingerRoutine(for exercise: FingerExercise) -> FingerRoutine {
        var routine = homeModel(for: exercise.category).routine

        if let counts = customCounts(for: exercise.rawValue) {
            routine.sets = counts.sets ?? routine.sets
            routine.repetitions = counts.repetitions ?? routine.repetitions
        }

        return routine
    }

    /// Freeze the finished side before the plan selects a different item.
    func markOppositionRest(_ side: HandSide?) {
        oppositionRestSide = side
    }

    /// The recorded long-rest set for the finished scripted exercise.
    ///
    /// Both thumb-opposition briefs approve the same long-rest wording, but only the right-hand
    /// generator rendered it. The left hand therefore shares those Marizka clips instead of
    /// falling back to the older generic `rest.long.*` recordings.
    var longRestNarrationPrefix: String? {
        if oppositionRestSide != nil {
            return "opposition.right.longRest."
        }
        return armRaiseRestSide.map { ArmRaiseGuidance.prefix(for: $0) + "longRest." }
    }

    func usesArmRaiseScript(itemID: String) -> Bool {
        guard AppLanguage.selected == .indonesian,
              let item = items.first(where: { $0.id == itemID }),
              case .therapy(.armRaise) = item.exercise else {
            return false
        }
        return armRaiseScriptSide != nil
    }

    // MARK: - Scripted arm raise

    /// The arms the approved Indonesian arm-raise briefs train, in order: left, then right.
    /// A chosen plan side runs that arm only. `nil` keeps the program's own guidance.
    /// The briefs apply even with custom debug counts; their two sets of five win.
    private var armRaiseScriptSides: [TherapySide]? {
        guard AppLanguage.selected == .indonesian else {
            return nil
        }

        guard let selectedSide else {
            return [.left, .right]
        }

        return [selectedSide == .left ? .left : .right]
    }

    /// The arm the next or open arm-raise session trains, while the briefs apply.
    var armRaiseScriptSide: TherapySide? {
        guard let sides = armRaiseScriptSides else {
            return nil
        }

        return pendingArmRaiseSide.flatMap { sides.contains($0) ? $0 : nil } ?? sides.first
    }

    /// The arm after `side` that still needs its own full session, if any.
    private func armRaiseSide(after side: TherapySide) -> TherapySide? {
        guard let sides = armRaiseScriptSides,
              let index = sides.firstIndex(of: side),
              sides.indices.contains(index + 1) else {
            return nil
        }

        return sides[index + 1]
    }

    func markArmRaiseRest(_ side: TherapySide?) {
        armRaiseRestSide = side
    }

    func balanceSettings(for exercise: BalanceExercise) -> BalancePracticeSettings {
        var settings = BalancePracticeSettings(exercise: exercise)
        if !exercise.isSitToStand, let side = selectedSide {
            settings.armSelection = side == .left ? .left : .right
        }

        if let counts = customCounts(for: exercise.rawValue) {
            let range = BalancePracticeSettings.setsRange
            let sets = counts.sets ?? settings.sets
            settings.sets = min(range.upperBound, max(range.lowerBound, sets))
            settings.repetitions = counts.repetitions ?? settings.repetitions
        }

        return settings
    }

    private func homeModel(for category: ExerciseCategory) -> FingerHomeViewModel {
        category == .fingers ? fingers : forearm
    }

    private func routineModel(for category: TherapyCategory) -> RoutineViewModel {
        switch category {
        case .arm:
            return armRoutine
        case .taskOriented:
            return taskRoutine
        }
    }

    /// Applies the daily-plan side to the saved exercise configuration for this session.
    func routineExercise(for kind: TherapyKind) -> RoutineExercise {
        guard let category = kind.category else {
            return RoutineExercise(kind: kind)
        }

        let configuration = routineModel(for: category).configuration
        var exercise = configuration.exercises.first { $0.kind == kind } ?? RoutineExercise(kind: kind)
        if let side = selectedSide {
            exercise.sides = side == .left ? .left : .right
        }

        if let counts = customCounts(for: kind.rawValue) {
            exercise.sets = counts.sets ?? exercise.sets

            // Arm movements and the towel count goals per side; directional reach counts rounds.
            if let repetitions = counts.repetitions {
                exercise.leftGoal = repetitions
                exercise.rightGoal = repetitions
                exercise.rounds = repetitions
            }
        }

        // The briefs run one arm per session, two sets of five unless the plan's counts are
        // customized; the script then speaks only the recordings that match the counts.
        if kind == .armRaise, let side = armRaiseScriptSide {
            let counts = customCounts(for: kind.rawValue)
            let repetitions = counts?.repetitions ?? ScriptedRepetitions.recordedRepetitions
            exercise.sides = side == .left ? .left : .right
            exercise.sets = counts?.sets ?? ScriptedRepetitions.recordedSets
            exercise.leftGoal = repetitions
            exercise.rightGoal = repetitions
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
    func begin(from itemID: String? = nil) {
        let chosen = itemID.flatMap { id in items.firstIndex { $0.id == id } }

        guard let index = chosen ?? nextIndex ?? items.indices.first else {
            return
        }

        isRunning = true
        currentIndex = index
        pendingArmRaiseSide = nil
        router.showIntro(itemID: items[index].id)
    }

    /// "Mulai Latihan" on an intro: validates permissions and listening once, as an explicit
    /// start requires, then opens that item's session.
    func startCurrent(
        readiness: TherapyReadinessViewModel
    ) async {
        guard isRunning, let currentIndex else {
            return
        }

        guard await readiness.performAction(),
              isRunning, self.currentIndex == currentIndex else {
            return
        }

        launch(currentIndex)
    }

    /// Called by a session's finishing action while the plan runs. Only a session that reached
    /// its goal counts as done. A completed item leads to rest, or to the day-complete page.
    func finish(completed: Bool) {
        guard isRunning, !restingBeforeNext, let currentIndex else {
            return
        }

        guard completed else {
            end()
            return
        }

        // The left arm's session is followed by the long rest, then the right arm's own intro
        // and session, as the two briefs describe. The same item stays current.
        if case .therapy(.armRaise) = items[currentIndex].exercise,
           let side = armRaiseScriptSide,
           let nextSide = armRaiseSide(after: side) {
            pendingArmRaiseSide = nextSide
            restingBeforeNext = true
            presentPlanNext()
            return
        }

        pendingArmRaiseSide = nil
        progress = progress.current(on: .now)
        progress.completed.insert(items[currentIndex].id)
        Task { await saveProgress() }

        let next = upcomingIndex
        self.currentIndex = next
        restingBeforeNext = next != nil
        presentPlanNext()
    }

    private func presentPlanNext() {
        if router.isCoverPresented {
            router.replaceCover(with: .planNext)
        } else {
            router.presentCover(.planNext)
        }
    }

    func launchAfterRest() {
        guard isRunning, restingBeforeNext, let currentIndex else {
            return
        }
        restingBeforeNext = false
        launch(currentIndex, replacingRest: true)
    }

    /// "Kembali" on an intro, "Kembali ke Beranda" after the last item, or leaving a session
    /// without continuing.
    func end() {
        isRunning = false
        restingBeforeNext = false
        currentIndex = nil
        pendingArmRaiseSide = nil
        router.endRun()
    }

    private func launch(
        _ index: Int,
        replacingRest: Bool = false
    ) {
        currentIndex = index
        oppositionRestSide = nil
        armRaiseRestSide = nil
        let route: PlanCoverRoute

        switch items[index].exercise {
        case .finger(let exercise):
            let checkpoint = homeModel(for: exercise.category).checkpoint
            let side = selectedSide
            let matchesSide = side.map { checkpoint?.routine.side == $0 } ?? true
            let routine = fingerRoutine(for: exercise)

            // A checkpoint saved under other counts would not run what the card shows.
            let matchesCounts = checkpoint.map {
                $0.routine.sets == routine.sets
                    && $0.routine.repetitions == routine.repetitions
            } ?? true

            fingerSessionService.prepare(
                category: exercise.category,
                continuing: checkpoint?.routine.only == exercise && matchesSide && matchesCounts,
                only: exercise,
                side: side,
                sets: routine.sets,
                repetitions: routine.repetitions
            )
            route = .fingerSession

        case .therapy(let kind):
            let exercise = routineExercise(for: kind)
            let configuration = kind.category.map { routineModel(for: $0).configuration }
                ?? RoutineConfiguration()
            let routine = Routine(
                activities: exercise.activities,
                restSeconds: Double(configuration.restSeconds),
                practiceSeconds: Double(configuration.practiceSeconds)
            )
            route = .therapySession(routine)

        case .balance(let exercise):
            let settings = balanceSettings(for: exercise)
            route = .balanceSession(exercise: exercise, settings: settings)
        }

        if replacingRest {
            router.replaceCover(with: route)
        } else {
            router.presentCover(route)
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
