//
//  BalanceCompletionOverlay.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

struct BalanceCompletionOverlay: View {
    let metrics: BalanceMetrics
    let goal: Int
    let holdDuration: Double
    let voiceListening: Bool
    let repeatPractice: () -> Void
    let endPractice: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())

                ScrollView {
                    VStack(spacing: 20) {
                        TherapyCelebration()
                            .frame(height: 130)

                        VStack(spacing: 6) {
                            Text("balance.completion.title")
                                .typography(.largeTitle)
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)
                            Text("balance.completion.subtitle")
                                .typography(.body)
                                .foregroundStyle(TherapyPalette.muted)
                                .multilineTextAlignment(.center)
                        }

                        BalanceSessionSummary(
                            metrics: metrics,
                            goal: goal,
                            holdDuration: holdDuration
                        )

                        Label(
                            voiceListening
                                ? "balance.completion.voiceCommands"
                                : "balance.completion.touchCommands",
                            systemImage: voiceListening ? "waveform" : "hand.tap.fill"
                        )
                        .typography(.headline)
                        .foregroundStyle(
                            voiceListening ? TherapyPalette.green : TherapyPalette.muted
                        )
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(TherapyPalette.mint, in: RoundedRectangle(cornerRadius: 18))

                        HStack(spacing: 16) {
                            TherapyButton(
                                title: "balance.completion.end",
                                symbol: "xmark.circle",
                                secondary: true,
                                action: endPractice
                            )
                            TherapyButton(
                                title: "balance.completion.repeat",
                                symbol: "arrow.counterclockwise",
                                action: repeatPractice
                            )
                        }
                    }
                    .padding(28)
                }
                .frame(
                    maxWidth: 900,
                    maxHeight: max(320, geometry.size.height - 48)
                )
                .background(TherapyPalette.surface, in: RoundedRectangle(cornerRadius: 34))
                .overlay {
                    RoundedRectangle(cornerRadius: 34)
                        .strokeBorder(TherapyPalette.green.opacity(0.28), lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.28), radius: 32, y: 14)
                .padding(24)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("balance.completion.accessibility")
    }
}
