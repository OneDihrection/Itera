//
//  DailyPlanIntroView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The page before each daily-plan exercise: what it trains, today's target, a safety note
/// and the explicit Start that validates readiness and opens the session.
struct TMDailyPlanIntroView<ViewModel: DailyPlanIntroViewModelProtocol>: View {
    @State private var viewModel: ViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if let row = viewModel.row {
            intro(row)
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .task {
                    viewModel.appear()
                }
                .onDisappear {
                    viewModel.disappear()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        viewModel.pauseNarration()
                    }
                }
        }
    }

    private func intro(_ row: DailyPlanRow) -> some View {
        TMTherapyExerciseIntro(
            heading: TMTherapyExerciseHeading(
                eyebrow: Text("plan.exerciseNumber \(viewModel.exerciseNumber)"),
                title: Text(LocalizedStringKey(row.titleKey))
            ),
            focusTitle: "plan.focusTitle",
            focus: Text(LocalizedStringKey("plan.purpose." + viewModel.itemID)),
            targetTitle: "plan.targetTitle",
            safetyNote: "exercise.safetyNote",
            startTitle: LocalizedStringKey(viewModel.startTitleKey),
            startDisabled: viewModel.startDisabled,
            message: viewModel.readinessMessageKey.map { Text(LocalizedStringKey($0)) },
            countdownSeconds: viewModel.countdownSeconds,
            onBack: viewModel.back,
            onStart: viewModel.start
        ) {
            demonstration
        } targets: {
            targets(row.details)
        }
    }

    // MARK: - Content

    /// Each exercise's own instruction video or animation.
    @ViewBuilder
    private var demonstration: some View {
        switch viewModel.demonstration {
        case .finger(let exercise, let side):
            TMFingerExampleView(
                exercise: exercise,
                phase: .demonstration,
                returning: false,
                finger: 0,
                side: side,
                paused: false
            )

        case .towel:
            TMTowelDemonstrationView()

        case .movement(let asset, let mirrored):
            TMExerciseExample(
                asset: asset,
                mirrored: mirrored,
                mode: .looping
            )

        case .balance(let exercise, let settings):
            TMBalanceExerciseDemonstrationView(
                exercise: exercise,
                paused: false,
                arm: settings.armSelection.initialArm,
                selection: settings.armSelection
            )

        case nil:
            EmptyView()
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
        let orderedDetails = viewModel.usesScript ? sets + otherDetails : otherDetails + sets

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
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockDailyPlanIntroViewModel: DailyPlanIntroViewModelProtocol {
    let itemID = "armRaise"
    let row: DailyPlanRow? = nil
    let exerciseNumber = 2
    let demonstration: DailyPlanIntroDemonstration? = .movement(.armRaise, mirrored: false)
    let usesScript = false
    let countdownSeconds: Int? = nil
    let startTitleKey = "exercise.start"
    let startDisabled = false
    let readinessMessageKey: String? = nil

    func appear() {}
    func disappear() {}
    func pauseNarration() {}
    func start() {}
    func back() {}
}

/// The page renders only with a plan row, so this preview checks that the screen builds
/// against a mock; fill `row` from `DailyPlan.standard` to see the layout.
#Preview("Plan intro") {
    TMDailyPlanIntroView(viewModel: MockDailyPlanIntroViewModel())
}
#endif
