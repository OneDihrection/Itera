//
//  DailyPlanIntroView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The page before each daily-plan exercise: what it trains, today's target, a safety note
/// and the explicit Start that validates readiness and opens the session.
struct DailyPlanIntroView: View {
    let itemID: String

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
                    prepareReadiness()
                }
        }
    }

    private var row: DailyPlanRow? {
        dependencies.dailyPlan.rows(in: dependencies).first { $0.id == itemID }
    }

    private func intro(_ row: DailyPlanRow) -> some View {
        TherapyExerciseIntro(
            heading: TherapyExerciseHeading(
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
            onBack: {
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
        case .finger(let category):
            FingerExampleView(
                exercise: category.exercises.first ?? .fullFist,
                phase: .demonstration,
                returning: false,
                finger: 0,
                side: dependencies.homeModel(for: category).routine.side,
                paused: false
            )

        case .therapy(.foldTowel):
            TowelDemonstrationView()

        case .therapy(let kind):
            ExerciseExample(
                asset: kind == .elbowBend ? .elbowBend : .armRaise,
                mirrored: false,
                mode: .looping
            )

        case .balance(let exercise):
            let settings = BalancePracticeSettings(exercise: exercise)
            BalanceExerciseDemonstrationView(
                exercise: exercise,
                paused: false,
                arm: settings.armSelection.initialArm,
                selection: settings.armSelection
            )
        }
    }

    @ViewBuilder
    private func targets(_ details: [DailyPlanRow.Detail]) -> some View {
        TherapyStatRow {
            ForEach(details.indices, id: \.self) { index in
                if index > 0 {
                    TherapyStatDivider()
                }
                target(details[index])
            }
        }
    }

    private func target(_ detail: DailyPlanRow.Detail) -> TherapyTargetStat {
        switch detail {
        case .repetitions(let count):
            return TherapyTargetStat(value: count, unit: Text("exercise.repetitionsUnit"))
        case .sets(let count):
            return TherapyTargetStat(value: count, unit: Text("exercise.setsUnit"))
        case .holdSeconds(let seconds):
            return TherapyTargetStat(value: seconds, unit: Text("balance.secondsUnit"))
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
