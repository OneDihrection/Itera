//
//  DailyPlanIntroView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The page before each daily-plan exercise: what it trains, today's sets, repetitions and an
/// estimate of the minutes, a safety note and the voice commands. It reads its introduction,
/// then validates readiness and opens the session on its own; there is no Start button and no
/// back button. Pause, End and Skip sit at the bottom of the page.
struct TMDailyPlanIntroView<ViewModel: DailyPlanIntroViewModelProtocol>: View {
    @State private var viewModel: ViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if let row = viewModel.row {
            if viewModel.isAfterRest {
                // The plan's cover has no stack of its own; the bar holds a readiness action.
                NavigationStack {
                    page(row)
                }
            } else {
                // Pushed on Beranda's stack; End leaves it, ending the plan.
                page(row)
            }
        }
    }

    private func page(_ row: DailyPlanRow) -> some View {
        intro(row)
            .overlay {
                if viewModel.isPreparingSession {
                    TMLoadingOverlay(message: "loading.preparingSession")
                }
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.2),
                value: viewModel.isPreparingSession
            )
            .navigationBarTitleDisplayMode(.inline)
            // End on the page is the way out, so a swipe or back tap cannot skip the plan's end.
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .tabBar)
            .task {
                viewModel.appear()
            }
            .onDisappear {
                viewModel.disappear()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.becameActive()
                } else {
                    viewModel.pauseNarration()
                }
            }
    }

    private func intro(_ row: DailyPlanRow) -> some View {
        TMTherapyExerciseIntro(
            heading: TMTherapyExerciseHeading(
                title: Text(LocalizedStringKey(row.titleKey))
            ),
            focusTitle: "plan.focusTitle",
            focus: Text(LocalizedStringKey("plan.purpose." + viewModel.itemID)),
            message: viewModel.readinessMessageKey.map { Text(LocalizedStringKey($0)) },
            countdownSeconds: viewModel.countdownSeconds,
            actionTitle: viewModel.actionTitleKey.map { LocalizedStringKey($0) },
            actionDisabled: viewModel.actionDisabled,
            onAction: viewModel.performAction,
            flowActions: flowActions
        ) {
            demonstration
        } targets: {
            targets
        } notes: {
            notes
        }
    }

    /// Pause, End and Skip, except while the plan's countdown runs; the rest page around that
    /// intro shows its own.
    private var flowActions: TMTherapyIntroFlowActions? {
        guard viewModel.showsFlowActions else {
            return nil
        }

        return TMTherapyIntroFlowActions(
            paused: viewModel.narrationPaused,
            pause: viewModel.togglePause,
            stop: viewModel.exit,
            skip: viewModel.skip
        )
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

    /// Sets, repetitions and the estimated minutes, as three equal tiles.
    @ViewBuilder
    private var targets: some View {
        let counts = viewModel.counts
        let minutes = viewModel.estimatedMinutes

        TMTherapyStatTile(
            value: Text(counts.sets, format: .number),
            unit: unit(
                for: counts.sets,
                one: "plan.intro.setUnit",
                other: "plan.intro.setsUnit"
            )
        )

        TMTherapyStatTile(
            value: Text(counts.repetitions, format: .number),
            unit: unit(
                for: counts.repetitions,
                one: "plan.intro.repetitionUnit",
                other: "plan.intro.repetitionsUnit"
            )
        )

        TMTherapyStatTile(
            value: Text(verbatim: "\(minutes.lowerBound)–\(minutes.upperBound)"),
            unit: Text("plan.intro.minutesUnit")
        )
    }

    /// English says "1 set" but "3 sets"; a String Catalog plural must show its number, and
    /// the number has its own line here, so singular and plural are separate keys.
    private func unit(
        for count: Int,
        one: LocalizedStringKey,
        other: LocalizedStringKey
    ) -> Text {
        guard count == 1 else {
            return Text(other)
        }

        return Text(one)
    }

    /// Safety first, then how to pause and resume by voice.
    @ViewBuilder
    private var notes: some View {
        TMTherapyInfoCard(
            symbol: "info.circle",
            tint: TherapyPalette.warning,
            title: Text("plan.intro.safety.title"),
            message: Text("plan.intro.safety.message")
        )

        TMTherapyInfoCard(
            symbol: "mic.fill",
            tint: TherapyPalette.guidanceBlue,
            title: Text("plan.intro.voice.title"),
            message: Text("plan.intro.voice.message")
        )
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockDailyPlanIntroViewModel: DailyPlanIntroViewModelProtocol {
    let itemID = "armRaise"
    let row: DailyPlanRow? = nil
    let counts = (sets: 3, repetitions: 8)
    let estimatedMinutes = 5...8
    let demonstration: DailyPlanIntroDemonstration? = .movement(.armRaise, mirrored: false)
    let countdownSeconds: Int? = nil
    let isAfterRest = false
    let actionTitleKey: String? = nil
    let actionDisabled = false
    let isPreparingSession = false
    let readinessMessageKey: String? = nil
    let showsFlowActions = true
    let narrationPaused = false

    func appear() {}
    func disappear() {}
    func pauseNarration() {}
    func togglePause() {}
    func becameActive() {}
    func performAction() {}
    func exit() {}
    func skip() {}
}

/// The page renders only with a plan row, so this preview checks that the screen builds
/// against a mock; fill `row` from `DailyPlan.standard` to see the layout.
#Preview("Plan intro") {
    TMDailyPlanIntroView(viewModel: MockDailyPlanIntroViewModel())
}
#endif
