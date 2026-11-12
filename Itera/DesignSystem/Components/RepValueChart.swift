//
//  RepValueChart.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import Charts
import SwiftUI

/// One bar of `TMRepValueChart`. A nil value marks a repetition without a usable measurement.
struct TMRepValue: Identifiable {
    let repNumber: Int
    let value: Double?
    /// A short marker shown above an emphasized bar, such as "First".
    var marker: LocalizedStringKey? = nil

    var id: Int { repNumber }
}

/// A single-series bar strip with one bar per repetition, for reading change across a set.
///
/// Emphasized bars use the brand color and carry a text marker, so emphasis never relies on
/// color alone. Values are labeled with the caller's unit; the chart owns no measurement rules.
struct TMRepValueChart: View {
    let title: LocalizedStringKey
    let values: [TMRepValue]
    /// Appended to axis and accessibility values, for example "°".
    let unit: String
    var height: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .typography(.subheadline, weight: .semiBold)
                .foregroundStyle(TherapyPalette.muted)

            chart
        }
    }

    private var chart: some View {
        Chart(values) { item in
            if let value = item.value {
                BarMark(
                    x: .value("Repetition", String(item.repNumber)),
                    y: .value("Value", value),
                    width: .ratio(0.6)
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                .foregroundStyle(item.marker == nil ? TherapyPalette.progressSoftBar : TherapyPalette.brand)
                .annotation(position: .top, spacing: 4) {
                    if let marker = item.marker {
                        Text(marker)
                            .typography(.caption2, weight: .semiBold)
                            .foregroundStyle(TherapyPalette.ink)
                    }
                }
                .accessibilityLabel(Text("replay.repetition \(item.repNumber)"))
                .accessibilityValue(Text(verbatim: "\(Int(value.rounded()))\(unit)"))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { mark in
                AxisGridLine()
                    .foregroundStyle(TherapyPalette.outline)
                AxisValueLabel {
                    if let value = mark.as(Double.self) {
                        Text(verbatim: "\(Int(value))\(unit)")
                            .typography(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { mark in
                AxisValueLabel {
                    if let repetition = mark.as(String.self) {
                        Text(verbatim: repetition)
                            .typography(.caption)
                    }
                }
            }
        }
        .frame(height: height)
    }
}
