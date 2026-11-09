//
//  BalanceOverviewView.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

struct BalanceOverviewView: View {
    let exercise: BalanceExercise
    @Environment(NavigationRouter.self) private var router
    @AppStorage private var repetitions: Int
    @AppStorage private var holdSeconds: Int
    @AppStorage private var armSelectionRaw: String
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

                TherapyCard(color: TherapyPalette.hero) {
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
                            BalanceExerciseDemonstrationView(
                                exercise: exercise,
                                paused: animationPaused,
                                selection: BalanceArmSelection(rawValue: armSelectionRaw) ?? .both
                            )
                                .frame(width: 360, height: 260)
                            TherapyIconButton(
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

                TherapyCard {
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
                        TherapyAdjustmentControl(
                            title: exercise.localized("repetitions"),
                            value: $repetitions,
                            range: 2...20,
                            suffix: exercise.localized("touchUnit")
                        )
                        if !exercise.isSitToStand {
                            TherapyAdjustmentControl(
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

                TherapyButton(title: exercise.localized("begin"), symbol: "camera.fill") {
                    router.push(.balanceSession(
                        exercise: exercise,
                        repetitions: repetitions,
                        holdSeconds: holdSeconds,
                        armSelection: BalanceArmSelection(rawValue: armSelectionRaw) ?? .both
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
        TherapyCard {
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
