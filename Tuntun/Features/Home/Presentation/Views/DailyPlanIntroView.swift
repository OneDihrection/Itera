//
//  DailyPlanIntroView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The page before each daily-plan exercise: what it trains, today's target, a safety note
/// and the explicit Start that validates readiness and opens the session.
struct TMDailyPlanIntroView: View {
    private let itemID: String
    private let countdownSeconds: Int?
    private let automatic: Bool
    private let plan: DailyPlanViewModel
    private let audio: SessionAudioService
    private let permissions: PermissionManager
    /// Readiness waits for interrupted-session recovery before therapy can start.
    private let history: any HistoryRecovering

    @Environment(NavigationRouter.self) private var router

    @State private var readiness: HomeViewModel?
    @State private var starting = false
    @State private var narration = DailyPlanIntroNarration()
    @Environment(\.scenePhase) private var scenePhase

    private var usesArmRaiseScript: Bool {
        plan.usesArmRaiseScript(itemID: itemID)
    }

    private var usesScript: Bool {
        usesArmRaiseScript || plan.usesOppositionScript(itemID: itemID)
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

    /// - Parameters:
    ///   - countdownSeconds: shown in place of Start when the plan opens this intro after a rest.
    ///   - automatic: the intro was opened by the plan, so its reading leads into the session.
    init(
        itemID: String,
        countdownSeconds: Int? = nil,
        automatic: Bool = false,
        plan: DailyPlanViewModel,
        audio: SessionAudioService,
        permissions: PermissionManager,
        history: any HistoryRecovering
    ) {
        self.itemID = itemID
        self.countdownSeconds = countdownSeconds
        self.automatic = automatic
        self.plan = plan
        self.audio = audio
        self.permissions = permissions
        self.history = history
    }

    var body: some View {
        if let row {
            intro(row)
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .task {
                    prepareReadiness()
                    if usesScript {
                        start()
                    }
                }
                .onDisappear { narration.stop() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        narration.pause()
                    }
                }
        }
    }

    private var row: DailyPlanRow? {
        plan.rows().first { $0.id == itemID }
    }

    private func intro(_ row: DailyPlanRow) -> some View {
        TMTherapyExerciseIntro(
            heading: TMTherapyExerciseHeading(
                eyebrow: Text("plan.exerciseNumber \(plan.number(of: itemID))"),
                title: Text(LocalizedStringKey(row.titleKey))
            ),
            focusTitle: "plan.focusTitle",
            focus: Text(LocalizedStringKey("plan.purpose." + itemID)),
            targetTitle: "plan.targetTitle",
            safetyNote: "exercise.safetyNote",
            startTitle: narration.paused ? "session.resume" : "exercise.start",
            startDisabled: startDisabled,
            message: readinessMessage,
            countdownSeconds: usesScript ? nil : countdownSeconds,
            onBack: {
                narration.stop()
                if countdownSeconds != nil {
                    audio.cancelSpeech()
                }
                plan.end(router: router)
            },
            onStart: start
        ) {
            demonstration(for: row.item)
        } targets: {
            targets(row.details)
        }
    }

    // MARK: - Content

    /// Each exercise's own instruction video or animation.
    @ViewBuilder
    private func demonstration(for item: DailyPlanItem) -> some View {
        switch item.exercise {
        case .finger(let exercise):
            TMFingerExampleView(
                exercise: exercise,
                phase: .demonstration,
                returning: false,
                finger: 0,
                side: plan.fingerSide(for: exercise),
                paused: false
            )

        case .therapy(.foldTowel):
            TMTowelDemonstrationView()

        case .therapy(let kind):
            let exercise = plan.routineExercise(for: kind)
            TMExerciseExample(
                asset: kind == .elbowBend ? .elbowBend : kind == .directionalReach ? .directionalReach : .armRaise,
                mirrored: exercise.activities.first?.side == .left,
                mode: .looping
            )

        case .balance(let exercise):
            let settings = plan.balanceSettings(for: exercise)
            TMBalanceExerciseDemonstrationView(
                exercise: exercise,
                paused: false,
                arm: settings.armSelection.initialArm,
                selection: settings.armSelection
            )
        }
    }

    @ViewBuilder
    private func targets(_ details: [DailyPlanRow.Detail]) -> some View {
        let sets = details.filter { detail in
            if case .sets = detail {
                return true
            }
            return false
        }
        let otherDetails = details.filter { !sets.contains($0) }
        let orderedDetails = usesScript ? sets + otherDetails : otherDetails + sets

        TMTherapyStatRow {
            ForEach(orderedDetails.indices, id: \.self) { index in
                if index > 0 {
                    TMTherapyStatDivider()
                }
                target(orderedDetails[index])
            }
        }
    }

    private func target(_ detail: DailyPlanRow.Detail) -> TMTherapyTargetStat {
        switch detail {
        case .repetitions(let count):
            return TMTherapyTargetStat(value: count, unit: Text("exercise.repetitionsUnit"))
        case .sets(let count):
            return TMTherapyTargetStat(value: count, unit: Text("exercise.setsUnit"))
        case .holdSeconds(let seconds):
            return TMTherapyTargetStat(value: seconds, unit: Text("balance.secondsUnit"))
        }
    }

    // MARK: - Start

    /// Shown only when something blocks the start, such as a missing permission.
    private var readinessMessage: Text? {
        guard let readiness, !readiness.ready, readiness.message != "home.setup" else {
            return nil
        }

        return Text(LocalizedStringKey(readiness.message))
    }

    private func prepareReadiness() {
        if readiness == nil {
            readiness = HomeViewModel(
                permissions: permissions,
                audio: audio,
                history: history
            )
        }

        readiness?.refresh()
    }

    private func start() {
        if narration.paused {
            narration.resume()
            return
        }

        guard let readiness, !starting else {
            return
        }

        starting = true
        Task {
            if usesScript {
                await narration.start(
                    readiness: readiness,
                    plan: plan,
                    audio: audio,
                    router: router,
                    itemID: itemID,
                    automatic: automatic,
                    lines: scriptIntroduction
                )
                starting = false
            } else {
                await plan.startCurrent(
                    readiness: readiness,
                    router: router
                )
                starting = false
            }
        }
    }

    /// Mulai Latihan waits until the scripted intro has been read in full, so the patient hears
    /// every instruction before the session opens. While the intro is paused the same button
    /// reads "Lanjutkan" and stays enabled to resume it.
    private var startDisabled: Bool {
        guard !narration.paused else {
            return false
        }

        return starting || narration.running
    }
}
