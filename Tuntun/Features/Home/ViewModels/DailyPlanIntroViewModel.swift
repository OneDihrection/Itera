//
//  DailyPlanIntroViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

/// The instruction example an intro shows for its exercise.
enum DailyPlanIntroDemonstration {
    case finger(FingerExercise, side: HandSide)
    case towel
    case movement(ExerciseAnimationAsset, mirrored: Bool)
    case balance(BalanceExercise, settings: BalancePracticeSettings)
}

@MainActor
protocol DailyPlanIntroViewModelProtocol: AnyObject, Observable {
    var itemID: String { get }
    var row: DailyPlanRow? { get }
    /// The sets and repetitions this exercise runs with now, Settings' choices included.
    var counts: (sets: Int, repetitions: Int) { get }
    /// About how long the exercise takes, in whole minutes (`DailyPlanDuration`).
    var estimatedMinutes: ClosedRange<Int> { get }
    var demonstration: DailyPlanIntroDemonstration? { get }
    /// Shown when the plan opens this intro after a rest.
    var countdownSeconds: Int? { get }
    /// Opened by the plan inside its full-screen cover after a rest, rather than pushed on
    /// Beranda's stack, so it has no system back button and needs its own way out.
    var isAfterRest: Bool { get }
    /// The one control the page shows, and only when the intro cannot go on by itself:
    /// "Lanjutkan" while the narration is paused, or the readiness action ("Buka Pengaturan",
    /// "Coba lagi"…) when a missing permission or voice failure stopped the session opening.
    var actionTitleKey: String? { get }
    var actionDisabled: Bool { get }
    /// True while readiness validates listening and opens the session.
    var isPreparingSession: Bool { get }
    /// Set only when something blocks the start, such as a missing permission.
    var readinessMessageKey: String? { get }

    func appear()
    func disappear()
    func pauseNarration()
    /// The app is active again: resume a paused intro, or open the session if readiness was
    /// what held it back and is now satisfied (for example after Settings).
    func becameActive()
    func performAction()
    func back()

    #if DEBUG
    /// Skips the intro narration and opens the session at once.
    func startWithoutNarration()
    #endif
}

/// The page before each daily-plan exercise. Every intro opened from Beranda reads its
/// introduction first (the scripted brief, or the exercise's purpose), then validates readiness
/// and opens the session on its own; there is no Start button (2026-11-23). A control appears
/// only when the intro cannot go on by itself: "Lanjutkan" after an interruption, or the
/// readiness action when a permission or voice check blocks the session.
@MainActor
@Observable
final class DailyPlanIntroViewModel: DailyPlanIntroViewModelProtocol {
    let itemID: String
    private(set) var starting = false

    @ObservationIgnored private let presetCountdown: Int?
    @ObservationIgnored private let automatic: Bool
    private let plan: DailyPlanViewModel
    @ObservationIgnored private let audioService: SessionAudioService
    private let readiness: TherapyReadinessViewModel
    private let narration: DailyPlanIntroNarration

    /// - Parameters:
    ///   - countdownSeconds: shown when the plan opens this intro after a rest.
    ///   - automatic: the intro was opened by the plan, so its reading leads into the session.
    init(
        itemID: String,
        countdownSeconds: Int?,
        automatic: Bool,
        plan: DailyPlanViewModel,
        audioService: SessionAudioService,
        readiness: TherapyReadinessViewModel,
        narration: DailyPlanIntroNarration
    ) {
        self.itemID = itemID
        self.presetCountdown = countdownSeconds
        self.automatic = automatic
        self.plan = plan
        self.audioService = audioService
        self.readiness = readiness
        self.narration = narration
    }

    // MARK: - State

    var row: DailyPlanRow? {
        plan.rows().first { $0.id == itemID }
    }

    var counts: (sets: Int, repetitions: Int) {
        guard let item = row?.item else {
            return (1, 1)
        }

        return plan.counts(for: item)
    }

    var estimatedMinutes: ClosedRange<Int> {
        let counts = counts

        return DailyPlanDuration.minutes(
            sets: counts.sets,
            repetitions: counts.repetitions,
            restSeconds: plan.shortRestSeconds
        )
    }

    private var usesScript: Bool {
        usesArmRaiseScript
            || plan.usesFingerScript(itemID: itemID)
            || plan.usesBalanceScript(itemID: itemID)
            || plan.usesGuidedScript(itemID: itemID)
    }

    var countdownSeconds: Int? {
        usesScript ? nil : presetCountdown
    }

    var isAfterRest: Bool {
        automatic || presetCountdown != nil
    }

    var actionTitleKey: String? {
        if narration.paused {
            return "session.resume"
        }

        guard countdownSeconds == nil,
              !narration.running,
              !starting,
              readinessMessageKey != nil else {
            return nil
        }

        return readiness.action
    }

    var actionDisabled: Bool {
        starting
    }

    var isPreparingSession: Bool {
        readiness.preparingSession
    }

    var readinessMessageKey: String? {
        guard !readiness.ready, readiness.message != "home.setup" else {
            return nil
        }

        return readiness.message
    }

    var demonstration: DailyPlanIntroDemonstration? {
        guard let item = row?.item else {
            return nil
        }

        switch item.exercise {
        case .finger(let exercise):
            return .finger(exercise, side: plan.fingerSide(for: exercise))

        case .therapy(.foldTowel):
            return .towel

        case .therapy(let kind):
            let exercise = plan.routineExercise(for: kind)
            return .movement(
                Self.asset(for: kind),
                mirrored: exercise.activities.first?.side == .right
            )

        case .balance(let exercise):
            return .balance(exercise, settings: plan.balanceSettings(for: exercise))
        }
    }

    // MARK: - Actions

    func appear() {
        readiness.refresh()

        if narrates {
            start()
        }
    }

    func disappear() {
        narration.stop()
    }

    func pauseNarration() {
        narration.pause()
    }

    func becameActive() {
        if narration.paused {
            narration.resume()
            return
        }

        guard !starting else {
            return
        }

        readiness.refresh()

        // The intro already finished but readiness held the session back; it can open now.
        guard narration.finished, readiness.ready else {
            return
        }

        start()
    }

    func performAction() {
        start()
    }

    /// Reads the introduction, or, once it has been read, validates readiness and opens the
    /// session. While the reading is paused it resumes instead; while it runs it is skipped.
    private func start() {
        if narration.paused {
            narration.resume()
            return
        }

        if narration.running {
            skipNarration()
            return
        }

        guard !starting else {
            return
        }

        starting = true
        Task {
            if narrates, !narration.finished {
                await narration.start(
                    readiness: readiness,
                    plan: plan,
                    audioService: audioService,
                    itemID: itemID,
                    automatic: automatic,
                    lines: introductionLines
                )
            } else {
                await plan.startCurrent(readiness: readiness)
            }

            starting = false
        }
    }

    #if DEBUG
    func startWithoutNarration() {
        skipNarration()
    }
    #endif

    /// The after-rest intro's "Kembali" bar button. A pushed intro leaves through the system back
    /// button instead, and Beranda's screen model ends the plan; `disappear()` stops the reading.
    func back() {
        narration.stop()

        if presetCountdown != nil {
            audioService.cancelSpeech()
        }

        plan.end()
    }

    // MARK: - Helpers

    /// Stops the introduction where it is and opens the session the way its end would.
    /// Stopping clears the narration's completion, so the session never opens twice.
    private func skipNarration() {
        narration.stop()

        guard !starting else {
            return
        }

        starting = true
        Task {
            if automatic {
                plan.launchAfterRest()
            } else {
                await plan.startCurrent(readiness: readiness)
            }

            starting = false
        }
    }

    /// The after-rest intro of an unscripted exercise shows the plan's countdown instead, so
    /// speech never races it.
    private var narrates: Bool {
        usesScript || presetCountdown == nil
    }

    private var introductionLines: [NarrationLine] {
        guard usesScript else {
            return [NarrationLine(key: "plan.purpose." + itemID)]
        }

        return scriptIntroduction
    }

    private var usesArmRaiseScript: Bool {
        plan.usesArmRaiseScript(itemID: itemID)
    }

    /// The scripted intro for this item's side and counts.
    private var scriptIntroduction: [NarrationLine] {
        if plan.usesBalanceScript(itemID: itemID) {
            return plan.balanceIntroductionLines(itemID: itemID)
        }

        if plan.usesGuidedScript(itemID: itemID) {
            return plan.guidedIntroductionLines(itemID: itemID)
        }

        guard usesArmRaiseScript else {
            return plan.fingerIntroductionLines(itemID: itemID)
        }

        let activity = plan.routineExercise(for: .armRaise).activities.first
        return ArmRaiseGuidance.introduction(
            for: activity?.side ?? .left,
            sets: activity?.sets ?? ScriptedRepetitions.recordedSets,
            repetitions: activity?.goal ?? ScriptedRepetitions.recordedRepetitions
        )
    }

    private static func asset(for kind: TherapyKind) -> ExerciseAnimationAsset {
        switch kind {
        case .elbowBend:
            return .elbowBend
        case .directionalReach:
            return .directionalReach
        default:
            return .armRaise
        }
    }
}
