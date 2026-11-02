//
//  BalanceOverviewView.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

struct BalanceOverviewView: View {
    @Environment(NavigationRouter.self) private var router
    @AppStorage("balance.repetitions") private var repetitions = 6
    @AppStorage("balance.holdSeconds") private var holdSeconds = 10
    @State private var animationPaused = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("balance.title")
                    .typography(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("balance.subtitle")
                    .typography(.title2)
                    .foregroundStyle(TherapyPalette.muted)

                TherapyCard(color: TherapyPalette.hero) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 20) {
                            Label("balance.animation", systemImage: "sparkles")
                                .typography(.headline)
                                .foregroundStyle(TherapyPalette.green)
                            Text("balance.overview")
                                .typography(.body)
                            Label("balance.noEquipment", systemImage: "checkmark.circle.fill")
                                .typography(.headline)
                                .foregroundStyle(TherapyPalette.green)
                            Text("balance.animationHint")
                                .typography(.footnote)
                                .foregroundStyle(TherapyPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ZStack(alignment: .bottomTrailing) {
                            BalanceDemonstrationView(paused: animationPaused)
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
                        TherapyAdjustmentControl(
                            title: "balance.repetitions",
                            value: $repetitions,
                            range: 2...20,
                            suffix: "balance.touchUnit"
                        )
                        TherapyAdjustmentControl(
                            title: "balance.holdDuration",
                            value: $holdSeconds,
                            range: 3...20,
                            suffix: "balance.secondsUnit"
                        )
                        Text("balance.holdDurationHint")
                            .typography(.footnote)
                            .foregroundStyle(TherapyPalette.muted)
                        Text("balance.repetitionsHint")
                            .typography(.footnote)
                            .foregroundStyle(TherapyPalette.muted)
                    }
                }

                HStack(spacing: 20) {
                    instructionCard(
                        symbol: "person.crop.rectangle",
                        title: "balance.step.posture",
                        detail: "balance.step.posture.detail"
                    )
                    instructionCard(
                        symbol: "hand.raised.fingers.spread",
                        title: "balance.step.touch",
                        detail: "balance.step.touch.detail"
                    )
                    instructionCard(
                        symbol: "figure.mind.and.body",
                        title: "balance.step.balance",
                        detail: "balance.step.balance.detail"
                    )
                }

                TherapyButton(title: "balance.begin", symbol: "camera.fill") {
                    router.push(.balanceSession(
                        repetitions: repetitions,
                        holdSeconds: holdSeconds
                    ))
                }
            }
            .padding(28)
        }
        .background(TherapyPalette.cream)
        .navigationTitle("balance.title")
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
