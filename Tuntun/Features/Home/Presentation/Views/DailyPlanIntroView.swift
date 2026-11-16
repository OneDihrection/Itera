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
    let itemID: String
    var countdownSeconds: Int? = nil
    var automatic = false

    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(PermissionManager.self) private var permissions

    @State private var readiness: HomeViewModel?
    @State private var starting = false
    @State private var narration = DailyPlanIntroNarration()
    @Environment(\.scenePhase) private var scenePhase

    private var usesArmRaiseScript: Bool {
        dependencies.dailyPlan.usesArmRaiseScript(itemID: itemID, in: dependencies)
    }

    private var usesScript: Bool {
        usesArmRaiseScript || dependencies.dailyPlan.usesOppositionScript(itemID: itemID, in: dependencies)
    }

    /// The scripted intro for this item's side and counts.
    private var scriptIntroduction: [String] {
        guard usesArmRaiseScript else {
            return dependencies.dailyPlan.oppositionIntroductionKeys(in: dependencies)
        }

        let activity = dependencies.dailyPlan.routineExercise(for: .armRaise, in: dependencies).activities.first
        return ArmRaiseGuidance.introduction(
            for: activity?.side ?? .left,
            sets: activity?.sets ?? ScriptedRepetitions.recordedSets,
            repetitions: activity?.goal ?? ScriptedRepetitions.recordedRepetitions
        )
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
        dependencies.dailyPlan.rows(in: dependencies).first { $0.id == itemID }
    }

    private func intro(_ row: DailyPlanRow) -> some View {
        TMTherapyExerciseIntro(
            heading: TMTherapyExerciseHeading(
                eyebrow: Text("plan.exerciseNumber \(dependencies.dailyPlan.number(of: itemID))"),
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
                    dependencies.audio.cancelSpeech()
                }
                dependencies.dailyPlan.end(router: router)
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
                side: dependencies.dailyPlan.fingerSide(for: exercise, in: dependencies),
                paused: false
            )

        case .therapy(.foldTowel):
            TMTowelDemonstrationView()

        case .therapy(let kind):
            let exercise = dependencies.dailyPlan.routineExercise(for: kind, in: dependencies)
            TMExerciseExample(
                asset: kind == .elbowBend ? .elbowBend : kind == .directionalReach ? .directionalReach : .armRaise,
                mirrored: exercise.activities.first?.side == .left,
                mode: .looping
            )

        case .balance(let exercise):
            let settings = dependencies.dailyPlan.balanceSettings(for: exercise)
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
                audio: dependencies.audio,
                history: dependencies
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
                    dependencies: dependencies,
                    router: router,
                    itemID: itemID,
                    automatic: automatic,
                    lines: scriptIntroduction
                )
                starting = false
            } else {
                await dependencies.dailyPlan.startCurrent(
                    readiness: readiness,
                    dependencies: dependencies,
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
