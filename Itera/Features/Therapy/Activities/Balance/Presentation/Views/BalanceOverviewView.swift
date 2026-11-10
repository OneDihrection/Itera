//
//  BalanceOverviewView.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

struct TMBalanceOverviewView: View {
    let exercise: BalanceExercise
    @Environment(NavigationRouter.self) private var router
    @AppStorage private var repetitions: Int
    @AppStorage private var holdSeconds: Int
    @AppStorage private var armSelectionRaw: String
    @AppStorage private var sets: Int
    @AppStorage private var restSeconds: Int
    @State private var animationPaused = false

    init(exercise: BalanceExercise = .crossMidline) {
        self.exercise = exercise
        // Each exercise remembers its own settings; Balancing keeps its original keys.
        // The defaults are shared with BalancePracticeSettings, which the daily plan reads.
        _repetitions = AppStorage(
            wrappedValue: BalancePracticeSettings.defaultRepetitions,
            exercise.storageKey("repetitions")
        )
        _holdSeconds = AppStorage(
            wrappedValue: BalancePracticeSettings.defaultHoldSeconds,
            exercise.storageKey("holdSeconds")
        )
        _armSelectionRaw = AppStorage(
            wrappedValue: BalancePracticeSettings.defaultArmSelection.rawValue,
            exercise.storageKey("armSelection")
        )
        _sets = AppStorage(
            wrappedValue: BalancePracticeSettings.defaultSets,
            exercise.storageKey("sets")
        )
        _restSeconds = AppStorage(
            wrappedValue: BalancePracticeSettings.defaultRestSeconds,
            exercise.storageKey("restSeconds")
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(exercise.localized("title"))
                    .typography(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(exercise.localized("subtitle"))
                    .typography(.title2)
                    .foregroundStyle(TherapyPalette.muted)

                TMTherapyCard(color: TherapyPalette.hero) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 20) {
                            Label("balance.animation", systemImage: "sparkles")
                                .typography(.headline)
                                .foregroundStyle(TherapyPalette.green)
                            Text(exercise.localized("overview"))
                                .typography(.body)
                            Label("balance.noEquipment", systemImage: "checkmark.circle.fill")
                                .typography(.headline)
                                .foregroundStyle(TherapyPalette.green)
                            Text(exercise.localized("animationHint"))
                                .typography(.footnote)
                                .foregroundStyle(TherapyPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ZStack(alignment: .bottomTrailing) {
                            TMBalanceExerciseDemonstrationView(
                                exercise: exercise,
                                paused: animationPaused,
                                selection: BalanceArmSelection(rawValue: armSelectionRaw) ?? .both
                            )
                                .frame(width: 360, height: 260)
                            TMTherapyIconButton(
                                title: animationPaused ? "action.resume" : "action.pause",
                                symbol: animationPaused ? "play.fill" : "pause.fill",
                                size: 68
                            ) {
                                animationPaused.toggle()
                            }
                            .padding(12)
                        }
                    }
                }

                TMTherapyCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("balance.settings")
                            .typography(.headline)
                        if !exercise.isSitToStand {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("balance.armSelection")
                                    .typography(.body)
                                Picker("balance.armSelection", selection: $armSelectionRaw) {
                                    Text("balance.arm.right")
                                        .tag(BalanceArmSelection.right.rawValue)
                                    Text("balance.arm.left")
                                        .tag(BalanceArmSelection.left.rawValue)
                                    Text("balance.arm.both")
                                        .tag(BalanceArmSelection.both.rawValue)
                                }
                                .pickerStyle(.segmented)
                                .accessibilityHint("balance.armSelectionHint")
                                Text("balance.armSelectionHint")
                                    .typography(.footnote)
                                    .foregroundStyle(TherapyPalette.muted)
                            }
                            .padding(18)
                            .background(TherapyPalette.cream, in: RoundedRectangle(cornerRadius: 22))
                        }
                        TMTherapyAdjustmentControl(
                            title: exercise.localized("repetitions"),
                            value: $repetitions,
                            range: 2...20,
                            suffix: exercise.localized("touchUnit")
                        )
                        TMTherapyAdjustmentControl(
                            title: "balance.sets",
                            value: $sets,
                            range: BalancePracticeSettings.setsRange,
                            suffix: "exercise.setsUnit"
                        )
                        if sets > 1 {
                            TMTherapyAdjustmentControl(
                                title: "balance.restSeconds",
                                value: $restSeconds,
                                range: BalancePracticeSettings.restRange,
                                suffix: "balance.secondsUnit"
                            )
                        }
                        if !exercise.isSitToStand {
                            TMTherapyAdjustmentControl(
                                title: "balance.holdDuration",
                                value: $holdSeconds,
                                range: 3...20,
                                suffix: "balance.secondsUnit"
                            )
                        }
                        if exercise.isRotation {
                            Label(exercise.localized("targetCalibrated"), systemImage: "scope")
                                .typography(.footnote)
                                .foregroundStyle(TherapyPalette.green)
                        }
                        if !exercise.isSitToStand {
                            Text("balance.holdDurationHint")
                                .typography(.footnote)
                                .foregroundStyle(TherapyPalette.muted)
                        }
                        Text(exercise.localized("repetitionsHint"))
                            .typography(.footnote)
                            .foregroundStyle(TherapyPalette.muted)
                    }
                }

                HStack(spacing: 20) {
                    instructionCard(
                        symbol: "person.crop.rectangle",
                        title: exercise.localized("step.posture"),
                        detail: exercise.localized("step.posture.detail")
                    )
                    instructionCard(
                        symbol: "hand.raised.fingers.spread",
                        title: exercise.localized("step.touch"),
                        detail: exercise.localized("step.touch.detail")
                    )
                    instructionCard(
                        symbol: "figure.mind.and.body",
                        title: exercise.localized("step.balance"),
                        detail: exercise.localized("step.balance.detail")
                    )
                }

                TMTherapyButton(title: exercise.localized("begin"), symbol: "camera.fill") {
                    router.push(.balanceSession(
                        exercise: exercise,
                        settings: BalancePracticeSettings(exercise: exercise)
                    ))
                }
            }
            .padding(28)
        }
        .background(TherapyPalette.cream)
        .navigationTitle(exercise.localized("title"))
    }

    private func instructionCard(
        symbol: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        TMTherapyCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .typography(size: 40, weight: .bold)
                    .foregroundStyle(TherapyPalette.green)
                    .accessibilityHidden(true)
                Text(title).typography(.headline)
                Text(detail).typography(.footnote).foregroundStyle(TherapyPalette.muted)
            }
        }
    }
}

extension BalanceExercise {
    func localized(_ name: String) -> LocalizedStringKey { LocalizedStringKey(key(name)) }
}
