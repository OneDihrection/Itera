//
//  BalanceSessionSummary.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import Charts
import SwiftUI

struct BalanceSessionSummary: View {
    let exercise: BalanceExercise
    let metrics: BalanceMetrics
    let goal: Int
    let holdDuration: Double

    private struct SummaryBar: Identifiable {
        let id: String
        let title: String
        let value: Double
        let displayValue: String
        let color: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("balance.summary.title")
                    .typography(.title2)
                Text("balance.summary.subtitle")
                    .typography(.footnote)
                    .foregroundStyle(TherapyPalette.muted)
            }

            Chart(summaryBars) { item in
                BarMark(
                    x: .value("balance.summary.normalizedValue", item.value),
                    y: .value("balance.summary.metric", item.title)
                )
                .foregroundStyle(item.color.gradient)
                .cornerRadius(8)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(verbatim: item.displayValue)
                        .typography(.footnote)
                        .foregroundStyle(TherapyPalette.ink)
                }
                .accessibilityLabel(item.title)
                .accessibilityValue(item.displayValue)
            }
            .chartXScale(domain: 0...1.35)
            .chartXAxis {
                AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number, format: .percent.precision(.fractionLength(0)))
                                .typography(.caption)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 230)
            .accessibilityLabel("balance.summary.chartAccessibility")

            HStack(spacing: 12) {
                if exercise.isRotation {
                    TherapyMetric(
                        title: "rotation.summary.peak",
                        value: "\(Int(metrics.peakRotation.rounded()))°"
                    )
                } else {
                    TherapyMetric(
                        title: "balance.summary.crossMidlineTime",
                        value: metrics.midlineDwellTime.formatted(
                            .number.precision(.fractionLength(1))
                        ) + "s"
                    )
                }
                TherapyMetric(
                    title: "balance.summary.prescribedHold",
                    value: prescribedHold.formatted(
                        .number.precision(.fractionLength(0))
                    ) + "s"
                )
            }

            Label("balance.summary.lowerCompensation", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(TherapyPalette.warning)
                .typography(.footnote)

            Label("balance.summary.notClinical", systemImage: "info.circle.fill")
                .foregroundStyle(TherapyPalette.muted)
                .typography(.footnote)
        }
        .padding(22)
        .background(TherapyPalette.cream, in: RoundedRectangle(cornerRadius: 24))
    }

    private var prescribedHold: Double {
        Double(goal) * holdDuration
    }

    private var summaryBars: [SummaryBar] {
        let completion = min(1, Double(metrics.completedTouches) / Double(max(1, goal)))
        let smoothness = min(1, max(0, metrics.pathSmoothness))
        let compensationLoad = min(
            1,
            Double(metrics.compensationEventsCount) / Double(max(1, goal))
        )

        return [
            SummaryBar(
                id: "completion",
                title: localized("balance.summary.completion"),
                value: completion,
                displayValue: "\(metrics.completedTouches)/\(goal)",
                color: TherapyPalette.green
            ),
            SummaryBar(
                id: "smoothness",
                title: localized("balance.summary.smoothness"),
                value: smoothness,
                displayValue: smoothness.formatted(
                    .percent.precision(.fractionLength(0))
                ),
                color: TherapyPalette.green
            ),
            SummaryBar(
                id: "compensation",
                title: localized("balance.summary.compensationLoad"),
                value: compensationLoad,
                displayValue: String(
                    format: localized("balance.summary.warningCount"),
                    metrics.compensationEventsCount
                ),
                color: TherapyPalette.warning
            ),
        ]
    }

    private func localized(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: AppLanguage.selected.resourceBundle,
            locale: AppLanguage.selected.locale
        )
    }
}
