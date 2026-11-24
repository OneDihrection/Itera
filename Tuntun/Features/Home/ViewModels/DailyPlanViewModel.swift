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
    private(set) var fingerScriptRestSide: HandSide?
    private(set) var armRaiseRestSide: TherapySide?
    /// The finished Balancing, elbow-bend or directional-reach session was narrated by a script.
    private(set) var scriptedSessionRest = false
    /// The second side of an item that runs one session per side (the scripted arm raise, a
    /// finger exercise on both hands), waiting behind its long rest. `nil` starts at the first
    /// side. The plan item is marked done only after its last side.
    private var pendingSecondSide: TherapySide?
    /// Sides chosen per exercise in Settings, by item id. Items without a choice use their
    /// program's saved side (`savedSide(of:)`).
    private(set) var sideChoices: [String: RoutineSides] = [:]
    /// Sets and repetitions chosen per exercise in Settings, by item id. A missing value keeps
    /// the program's own.
    private(set) var overrides: [String: DailyPlanOverrides] = [:]
    /// The rest between every set of every exercise, in seconds.
    private(set) var shortRestSeconds: Int
    /// Narrated breaths of the long rest between exercises and between sides.
    private(set) var longRestBreaths: Int

    var usesScriptedLongRest: Bool {
        fingerScriptRestSide != nil || armRaiseRestSide != nil || scriptedSessionRest
    }
    private(set) var errorKey: String?

    @ObservationIgnored private let repository: any DailyPlanProgressRepository
    @ObservationIgnored private let fingers: FingerHomeViewModel
    @ObservationIgnored private let forearm: FingerHomeViewModel
    @ObservationIgnored private let armRoutine: RoutineViewModel
    @ObservationIgnored private let taskRoutine: RoutineViewModel
    @ObservationIgnored private let fingerSessionService: FingerSessionService
    @ObservationIgnored private let router: any DailyPlanRouterProtocol
    @ObservationIgnored private var loadFailed = false

    /// Which exercises Beranda shows and their order, as arranged in Settings.
    private(set) var layout: DailyPlanLayout

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

        let defaults = UserDefaults.standard
        shortRestSeconds = DailyPlanOverrides.clamped(
            defaults.object(forKey: PracticePreferences.shortRestSeconds) as? Int
                ?? DailyPlanRest.defaultShortSeconds,
            to: DailyPlanRest.shortRange
        )
        longRestBreaths = DailyPlanOverrides.clamped(
            defaults.object(forKey: PracticePreferences.longRestBreaths) as? Int
                ?? DailyPlanRest.defaultLongBreaths,
            to: DailyPlanRest.longBreathsRange
        )

        let layout = DailyPlanLayout.load(for: items)
        self.layout = layout
        self.items = layout.items(from: items)

        sideChoices = Self.loadSideChoices(for: items)
        overrides = Self.loadOverrides(for: items)
    }

    // MARK: - Layout

    /// Saves the arrangement and rearranges Beranda. Ignored while a plan runs, so the open
    /// item's index never shifts under it.
    func applyLayout(_ layout: DailyPlanLayout) {
        guard !isRunning else {
            return
        }

        let reconciled = layout.reconciled(with: standardItems)
        reconciled.save()
        self.layout = reconciled
        items = reconciled.items(from: standardItems)
    }

    /// Every exercise shown, in the standard order.
    func resetLayout() {
        applyLayout(.standard(standardItems))
    }

    // MARK: - Counts

    /// The sets and repetitions `item` runs with now, Settings' choices included.
    func counts(
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

    func setSets(_ sets: Int, for item: DailyPlanItem) {
        let value = DailyPlanOverrides.clamped(sets, to: DailyPlanOverrides.setsRange)
        overrides[item.id, default: DailyPlanOverrides()].sets = value
        UserDefaults.standard.set(value, forKey: PracticePreferences.exerciseSets(item.id))
    }

    func setRepetitions(_ repetitions: Int, for item: DailyPlanItem) {
        let value = DailyPlanOverrides.clamped(repetitions, to: DailyPlanOverrides.repetitionsRange)
        overrides[item.id, default: DailyPlanOverrides()].repetitions = value
        UserDefaults.standard.set(value, forKey: PracticePreferences.exerciseRepetitions(item.id))
    }

    // MARK: - Rest

    /// Applies from the next session; a running session keeps the rest it started with.
    func setShortRestSeconds(_ seconds: Int) {
        shortRestSeconds = DailyPlanOverrides.clamped(seconds, to: DailyPlanRest.shortRange)
        UserDefaults.standard.set(shortRestSeconds, forKey: PracticePreferences.shortRestSeconds)
    }

    /// Applies from the next long rest; a long rest in progress keeps its count.
    func setLongRestBreaths(_ breaths: Int) {
        longRestBreaths = DailyPlanOverrides.clamped(breaths, to: DailyPlanRest.longBreathsRange)
        UserDefaults.standard.set(longRestBreaths, forKey: PracticePreferences.longRestBreaths)
    }

    /// Counts chosen in Settings, which replace the program's own (and, when they differ from the
    /// recording, the Indonesian scripts' recorded counts).
    private func customCounts(for itemID: String) -> (sets: Int?, repetitions: Int?)? {
        overrides[itemID].map { ($0.sets, $0.repetitions) }
    }

    private static func loadOverrides(for items: [DailyPlanItem]) -> [String: DailyPlanOverrides] {
        let defaults = UserDefaults.standard
        var loaded: [String: DailyPlanOverrides] = [:]

        for item in items {
            let value = DailyPlanOverrides(
                sets: defaults.object(forKey: PracticePreferences.exerciseSets(item.id)) as? Int,
                repetitions: defaults.object(forKey: PracticePreferences.exerciseRepetitions(item.id)) as? Int
            )

            if value != DailyPlanOverrides() {
                loaded[item.id] = value
            }
        }

        return loaded
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
        isRunning && !restingBeforeNext && (upcomingIndex != nil || awaitsSecondSide)
    }

    /// The open arm raise still has its other arm to run after the long rest.
    private var awaitsSecondSide: Bool {
        guard let currentIndex else {
            return false
        }

        let exercise = items[currentIndex].exercise

        guard let side = passSide(for: exercise) else {
            return false
        }

        return passSide(after: side, for: exercise) != nil
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

    // MARK: - Sides

    /// Sit to stand has no side; every other plan exercise offers right, left or both.
    func hasSide(_ item: DailyPlanItem) -> Bool {
        item.exercise != .balance(.sitToStand)
    }

    /// The side chosen for this exercise in Settings, or its program's saved side.
    func side(for item: DailyPlanItem) -> RoutineSides {
        sideChoices[item.id] ?? savedSide(of: item.exercise)
    }

    func setSide(_ side: RoutineSides, for item: DailyPlanItem) {
        sideChoices[item.id] = side
        UserDefaults.standard.set(side.rawValue, forKey: PracticePreferences.exerciseSide(item.id))
    }

    private func side(of exercise: DailyPlanItem.Exercise) -> RoutineSides {
        side(for: DailyPlanItem(exercise: exercise))
    }

    /// Saved per-exercise choices. A side chosen for the whole plan before per-exercise sides
    /// existed carries over to every item that has no choice of its own.
    private static func loadSideChoices(for items: [DailyPlanItem]) -> [String: RoutineSides] {
        let defaults = UserDefaults.standard
        let legacy = defaults.string(forKey: PracticePreferences.dailyPlanSide).flatMap(RoutineSides.init(rawValue:))
        var choices: [String: RoutineSides] = [:]

        for item in items {
            let saved = defaults.string(forKey: PracticePreferences.exerciseSide(item.id))
                .flatMap(RoutineSides.init(rawValue:))

            if let side = saved ?? legacy {
                choices[item.id] = side
            }
        }

        return choices
    }

    /// The side each program uses without a Settings choice: the finger routine's hand, the
    /// arm or task program's configuration, or the Balancing exercise's saved arm.
    private func savedSide(of exercise: DailyPlanItem.Exercise) -> RoutineSides {
        switch exercise {
        case .finger(let exercise):
            return homeModel(for: exercise.category).routine.side == .right ? .right : .left
        case .therapy(let kind):
            return configuredExercise(for: kind).sides
        case .balance(let exercise):
            let selection = BalancePracticeSettings(exercise: exercise).armSelection
            return RoutineSides(rawValue: selection.rawValue) ?? .both
        }
    }

    /// The sides an item runs as separate sessions, in order, or `nil` when one session covers
    /// its side or sides: the Indonesian arm-raise briefs, and a finger exercise on both hands
    /// (finger sessions track one hand).
    private func passes(for exercise: DailyPlanItem.Exercise) -> [TherapySide]? {
        switch exercise {
        case .therapy(.armRaise):
            return armRaiseScriptSides
        case .finger:
            return side(of: exercise) == .both ? [.left, .right] : nil
        case .therapy, .balance:
            return nil
        }
    }

    /// The side the next or open session of an item trains, when it runs one session per side.
    private func passSide(for exercise: DailyPlanItem.Exercise) -> TherapySide? {
        guard let sides = passes(for: exercise) else {
            return nil
        }

        guard isCurrent(exercise), let pendingSecondSide, sides.contains(pendingSecondSide) else {
            return sides.first
        }

        return pendingSecondSide
    }

    /// The side after `side` that still needs its own session, if any.
    private func passSide(after side: TherapySide, for exercise: DailyPlanItem.Exercise) -> TherapySide? {
        guard let sides = passes(for: exercise),
              let index = sides.firstIndex(of: side),
              sides.indices.contains(index + 1) else {
            return nil
        }

        return sides[index + 1]
    }

    private func isCurrent(_ exercise: DailyPlanItem.Exercise) -> Bool {
        currentIndex.map { items[$0].exercise == exercise } ?? false
    }

    /// The hand a finger session trains: this pass's hand on both hands, otherwise the chosen one.
    func fingerSide(for exercise: FingerExercise) -> HandSide {
        if let pass = passSide(for: .finger(exercise)) {
            return pass == .right ? .right : .left
        }

        return side(of: .finger(exercise)) == .right ? .right : .left
    }

    /// Whether the item's finger exercise runs an Indonesian hand script: a 2026-11-23 left-hand
    /// script, or the right hand's approved thumb-opposition script.
    func usesFingerScript(itemID: String) -> Bool {
        guard AppLanguage.selected == .indonesian,
              let exercise = fingerExercise(itemID: itemID) else {
            return false
        }
        return FingerScriptGuidance.isScripted(exercise, side: fingerSide(for: exercise))
    }

    /// The scripted intro for this item's side and counts; it names goals only when a
    /// recording states them truthfully.
    func fingerIntroductionLines(itemID: String) -> [NarrationLine] {
        guard let exercise = fingerExercise(itemID: itemID) else {
            return []
        }

        let side = fingerSide(for: exercise)
        let routine = fingerRoutine(for: exercise)
        if let script = FingerScriptGuidance.script(for: exercise, side: side) {
            return FingerScriptGuidance.introduction(script, sets: routine.sets, repetitions: routine.repetitions)
        }

        return OppositionGuidance.introductionKeys(for: side, routine: routine)
            .map { NarrationLine(key: $0) }
    }

    private func fingerExercise(itemID: String) -> FingerExercise? {
        guard let item = items.first(where: { $0.id == itemID }),
              case .finger(let exercise) = item.exercise else {
            return nil
        }
        return exercise
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
    func markFingerScriptRest(_ side: HandSide?) {
        fingerScriptRestSide = side
    }

    func markScriptedRest(_ scripted: Bool) {
        scriptedSessionRest = scripted
    }

    /// Whether the item's guided exercise runs a 2026-11-24 script: elbow bend or directional reach
    /// on the left arm alone, in an Indonesian plan. Arm raise keeps `usesArmRaiseScript`.
    func usesGuidedScript(itemID: String) -> Bool {
        guidedScriptActivity(itemID: itemID) != nil
    }

    /// The scripted intro for this item's side and counts.
    func guidedIntroductionLines(itemID: String) -> [NarrationLine] {
        guard let activity = guidedScriptActivity(itemID: itemID) else {
            return []
        }

        return GuidedScriptGuidance.introduction(
            activity.kind,
            side: activity.side,
            sets: activity.sets,
            repetitions: activity.goal
        )
    }

    private func guidedScriptActivity(itemID: String) -> SessionActivity? {
        guard AppLanguage.selected == .indonesian,
              let item = items.first(where: { $0.id == itemID }),
              case .therapy(let kind) = item.exercise,
              kind == .elbowBend || kind == .directionalReach,
              let activity = routineExercise(for: kind).activities.first,
              GuidedScriptGuidance.applies(to: activity) else {
            return nil
        }

        return activity
    }

    /// Whether the item's Balancing exercise runs a 2026-11-23 script: sit to stand, or a left-arm
    /// exercise in an Indonesian plan.
    func usesBalanceScript(itemID: String) -> Bool {
        balanceScript(itemID: itemID) != nil
    }

    /// The scripted intro for this item's counts; it names goals only when a recording states
    /// them truthfully.
    func balanceIntroductionLines(itemID: String) -> [NarrationLine] {
        guard let exercise = balanceExercise(itemID: itemID),
              let script = balanceScript(itemID: itemID) else {
            return []
        }

        let settings = balanceSettings(for: exercise)
        return BalanceScriptGuidance.introduction(script, sets: settings.sets, repetitions: settings.repetitions)
    }

    private func balanceScript(itemID: String) -> BalanceScript? {
        guard AppLanguage.selected == .indonesian,
              let exercise = balanceExercise(itemID: itemID) else {
            return nil
        }

        return BalanceScriptGuidance.script(for: exercise, arms: balanceSettings(for: exercise).armSelection)
    }

    private func balanceExercise(itemID: String) -> BalanceExercise? {
        guard let item = items.first(where: { $0.id == itemID }),
              case .balance(let exercise) = item.exercise else {
            return nil
        }
        return exercise
    }

    /// The recorded long-rest set for the finished scripted exercise.
    ///
    /// Every hand script approves the same long-rest wording, but only the right-hand opposition
    /// generator rendered it. The other hand scripts therefore share those Marizka clips instead
    /// of falling back to the older generic `rest.long.*` recordings.
    var longRestNarrationPrefix: String? {
        if fingerScriptRestSide != nil || scriptedSessionRest {
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

    /// The arms the approved Indonesian arm-raise briefs train, in order: both sides run left,
    /// then right, as two sessions; one side runs that arm only. `nil` keeps the program's own
    /// guidance. The briefs apply even with custom debug counts; their two sets of five win.
    private var armRaiseScriptSides: [TherapySide]? {
        guard AppLanguage.selected == .indonesian else {
            return nil
        }

        switch side(of: .therapy(.armRaise)) {
        case .left:
            return [.left]
        case .right:
            return [.right]
        case .both:
            return [.left, .right]
        }
    }

    /// The arm the next or open arm-raise session trains, while the briefs apply.
    var armRaiseScriptSide: TherapySide? {
        passSide(for: .therapy(.armRaise))
    }

    func markArmRaiseRest(_ side: TherapySide?) {
        armRaiseRestSide = side
    }

    func balanceSettings(for exercise: BalanceExercise) -> BalancePracticeSettings {
        var settings = BalancePracticeSettings(exercise: exercise)
        if !exercise.isSitToStand {
            settings.armSelection = BalanceArmSelection(rawValue: side(of: .balance(exercise)).rawValue)
                ?? settings.armSelection
        }

        if let counts = customCounts(for: exercise.rawValue) {
            let range = BalancePracticeSettings.setsRange
            let sets = counts.sets ?? settings.sets
            settings.sets = min(range.upperBound, max(range.lowerBound, sets))
            settings.repetitions = counts.repetitions ?? settings.repetitions
        }

        settings.restSeconds = shortRestSeconds

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

    /// The program's saved configuration for `kind`, before the plan applies its side and counts.
    private func configuredExercise(for kind: TherapyKind) -> RoutineExercise {
        guard let category = kind.category else {
            return RoutineExercise(kind: kind)
        }

        let configuration = routineModel(for: category).configuration
        return configuration.exercises.first { $0.kind == kind } ?? RoutineExercise(kind: kind)
    }

    /// Applies the exercise's side to the saved exercise configuration for this session. Both
    /// sides alternate within one session.
    func routineExercise(for kind: TherapyKind) -> RoutineExercise {
        var exercise = configuredExercise(for: kind)
        exercise.sides = side(of: .therapy(kind))

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
        pendingSecondSide = nil
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

        var opened = await readiness.performAction()

        // The intro has no Start button to tap a second time: when this attempt only asked for
        // permissions (or recovered history) and readiness is now satisfied, open at once.
        if !opened,
           readiness.ready,
           isRunning,
           self.currentIndex == currentIndex {
            opened = await readiness.performAction()
        }

        guard opened,
              isRunning,
              self.currentIndex == currentIndex else {
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

        // The first side's session is followed by the long rest, then the other side's own intro
        // and session (as the two arm-raise briefs describe). The same item stays current.
        let exercise = items[currentIndex].exercise
        if let side = passSide(for: exercise),
           let nextSide = passSide(after: side, for: exercise) {
            pendingSecondSide = nextSide
            restingBeforeNext = true
            presentPlanNext()
            return
        }

        pendingSecondSide = nil
        progress = progress.current(on: .now)
        progress.completed.insert(items[currentIndex].id)
        progress.planned = items.map(\.id)
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
        pendingSecondSide = nil
        router.endRun()
    }

    private func launch(
        _ index: Int,
        replacingRest: Bool = false
    ) {
        currentIndex = index
        fingerScriptRestSide = nil
        armRaiseRestSide = nil
        scriptedSessionRest = false
        let route: PlanCoverRoute

        switch items[index].exercise {
        case .finger(let exercise):
            let checkpoint = homeModel(for: exercise.category).checkpoint
            let side = fingerSide(for: exercise)
            let matchesSide = checkpoint.map { $0.routine.side == side } ?? true
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
                repetitions: routine.repetitions,
                restSeconds: shortRestSeconds
            )
            route = .fingerSession

        case .therapy(let kind):
            let exercise = routineExercise(for: kind)
            let configuration = kind.category.map { routineModel(for: $0).configuration }
                ?? RoutineConfiguration()
            let routine = Routine(
                activities: exercise.activities,
                restSeconds: Double(shortRestSeconds),
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
