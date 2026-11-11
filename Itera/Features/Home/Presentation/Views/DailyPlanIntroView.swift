//
//  DailyPlanIntroView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The page before each daily-plan exercise: what it trains, today's target, a safety note
/// and the explicit Start that validates readiness and opens the session.
struct TMDailyPlanIntroView: View {
    let itemID: String
    var countdownSeconds: Int? = nil

    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(PermissionManager.self) private var permissions

    @State private var readiness: HomeViewModel?
    @State private var starting = false

    var body: some View {
        if let row {
            intro(row)
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .task {
                    if countdownSeconds == nil {
                        prepareReadiness()
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
            startTitle: "exercise.start",
            startDisabled: starting,
            message: readinessMessage,
            countdownSeconds: countdownSeconds,
            onBack: {
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
        let orderedDetails = details.filter { !sets.contains($0) } + sets

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
        guard let readiness, !starting else {
            return
        }

        starting = true
        Task {
            await dependencies.dailyPlan.startCurrent(
                readiness: readiness,
                dependencies: dependencies,
                router: router
            )
            starting = false
        }
    }
}
