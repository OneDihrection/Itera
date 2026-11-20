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
    var exerciseNumber: Int { get }
    var demonstration: DailyPlanIntroDemonstration? { get }
    /// Scripted intros read their recorded introduction and show sets first.
    var usesScript: Bool { get }
    /// Shown in place of Start when the plan opens this intro after a rest.
    var countdownSeconds: Int? { get }
    var startTitleKey: String { get }
    var startDisabled: Bool { get }
    /// True while Start validates listening and opens the session.
    var isPreparingSession: Bool { get }
    /// Set only when something blocks the start, such as a missing permission.
    var readinessMessageKey: String? { get }

    func appear()
    func disappear()
    func pauseNarration()
    func start()
    func back()

    #if DEBUG
    /// Skips the intro narration and opens the session at once.
    func startWithoutNarration()
    #endif
}

/// The page before each daily-plan exercise. Start validates readiness once, as an explicit
/// start requires, then opens the session. Every intro opened from Beranda reads its
/// introduction first (the scripted brief, or the exercise's purpose) and then starts on its own;
/// Start during the reading skips the rest of it.
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
    ///   - countdownSeconds: shown in place of Start when the plan opens this intro after a rest.
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

    var exerciseNumber: Int {
        plan.number(of: itemID)
    }

    var usesScript: Bool {
        usesArmRaiseScript || plan.usesOppositionScript(itemID: itemID)
    }

    var countdownSeconds: Int? {
        usesScript ? nil : presetCountdown
    }

    var startTitleKey: String {
        narration.paused ? "session.resume" : "exercise.start"
    }

    /// Mulai Latihan stays enabled while the intro is read: tapping it skips the rest of the
    /// narration and opens the session. While the intro is paused the same button reads
    /// "Lanjutkan" and resumes it. It is disabled only while readiness is being validated.
    var startDisabled: Bool {
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

    func start() {
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

    private var introductionLines: [String] {
        guard usesScript else {
            return ["plan.purpose." + itemID]
        }

        return scriptIntroduction
    }

    private var usesArmRaiseScript: Bool {
        plan.usesArmRaiseScript(itemID: itemID)
    }

    /// The scripted intro for this item's side and counts.
    private var scriptIntroduction: [String] {
        guard usesArmRaiseScript else {
            return plan.oppositionIntroductionKeys()
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
