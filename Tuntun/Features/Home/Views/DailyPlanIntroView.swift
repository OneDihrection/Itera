//
//  DailyPlanIntroView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The page before each daily-plan exercise: what it trains, today's sets, repetitions and an
/// estimate of the minutes, a safety note and the voice commands. It reads its introduction,
/// then validates readiness and opens the session on its own; there is no Start button.
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
                // The plan's cover has no stack to go back through, so the page gets its own
                // navigation bar with a system bar button that leaves the plan.
                NavigationStack {
                    page(row)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                if !viewModel.isPreparingSession {
                                    Button("action.back", action: viewModel.back)
                                }
                            }
                        }
                }
            } else {
                // Pushed on Beranda's stack: the system back button pops it, and Beranda's
                // screen model ends the plan when the intro leaves the path.
                page(row)
            }
        }
    }

    private func page(_ row: DailyPlanRow) -> some View {
        intro(row)
            .overlay(alignment: .topLeading) {
                debugStartButton
            }
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
            // No way back while readiness opens the session.
            .navigationBarBackButtonHidden(viewModel.isPreparingSession)
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
            onAction: viewModel.performAction
        ) {
            demonstration
        } targets: {
            targets
        } notes: {
            notes
        }
    }

    // MARK: - Content

    /// Debug builds only: skips the intro narration and opens the session at once. It sits at the
    /// top left under the navigation bar, clear of the centred title.
    @ViewBuilder
    private var debugStartButton: some View {
        #if DEBUG
        if viewModel.countdownSeconds == nil {
            TMDebugActionButton(title: "debug.startExercise", symbol: "forward.end.fill") {
                viewModel.startWithoutNarration()
            }
            .padding(.top, 8)
            .padding(.leading, 24)
        }
        #endif
    }

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

    func appear() {}
    func disappear() {}
    func pauseNarration() {}
    func becameActive() {}
    func performAction() {}
    func back() {}
    func startWithoutNarration() {}
}

/// The page renders only with a plan row, so this preview checks that the screen builds
/// against a mock; fill `row` from `DailyPlan.standard` to see the layout.
#Preview("Plan intro") {
    TMDailyPlanIntroView(viewModel: MockDailyPlanIntroViewModel())
}
#endif
