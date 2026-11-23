//
//  RepValueChart.swift
//  Tuntun
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
                    x: .value("chart.axis.repetition", String(item.repNumber)),
                    y: .value("chart.axis.value", value),
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

// MARK: - Trend

/// One session on `TMTrendChart`.
struct TMTrendPoint: Identifiable {
    enum Highlight {
        case none
        /// The session compared against, drawn blue.
        case baseline
        /// The day shown, drawn larger in the brand colour with its value.
        case current
    }

    let id: Int
    let date: Date
    /// Already in the display unit, for example degrees or percent.
    let value: Double
    var highlight: Highlight = .none
    /// A short word above a highlighted point, such as "Awal", so emphasis is never colour alone.
    var marker: LocalizedStringKey? = nil
}

/// A small line chart of one value across sessions, evenly spaced so irregular practice days do
/// not stretch the line. Highlighted points carry a text marker; the current point also shows its
/// value. The caller supplies values in its unit; the chart owns no measurement rules. An optional
/// `caption` says how to read the line ("A rising line means your arm lifted higher").
struct TMTrendChart: View {
    let title: LocalizedStringKey
    let points: [TMTrendPoint]
    /// Appended to axis labels and accessibility values, for example "°".
    let unit: String
    var caption: Text? = nil
    var height: CGFloat = 220

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .typography(size: 18, weight: .semiBold, relativeTo: .subheadline)
                    .foregroundStyle(TherapyPalette.muted)

                if let caption {
                    caption
                        .typography(size: 17, weight: .regular, relativeTo: .subheadline)
                        .foregroundStyle(TherapyPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("chart.axis.session", point.id),
                    y: .value("chart.axis.value", point.value)
                )
                .foregroundStyle(TherapyPalette.planTrack)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            ForEach(points) { point in
                PointMark(
                    x: .value("chart.axis.session", point.id),
                    y: .value("chart.axis.value", point.value)
                )
                .symbolSize(symbolSize(point.highlight))
                .foregroundStyle(color(point.highlight))
                .annotation(
                    position: .top,
                    spacing: 6,
                    // Keeps markers whole near the chart's edges instead of truncating them.
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    annotation(point)
                        .fixedSize()
                }
                .accessibilityLabel(Text(point.date, format: .dateTime.day().month(.abbreviated).locale(locale)))
                .accessibilityValue(Text(verbatim: "\(Int(point.value.rounded()))\(unit)"))
            }
        }
        .chartXScale(domain: -0.4...(Double(max(points.count - 1, 1)) + 0.4))
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { mark in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
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
            AxisMarks(values: points.map(\.id)) { mark in
                AxisValueLabel {
                    if let index = mark.as(Int.self),
                       let point = points.first(where: { $0.id == index }),
                       showsDate(point) {
                        Text(point.date, format: .dateTime.day().month(.abbreviated).locale(locale))
                            .typography(.caption)
                            .fixedSize()
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            // Keeps the outer dots and their markers clear of the axis labels.
            plot.padding(.horizontal, 8)
        }
        .frame(height: height)
    }

    /// The values' span with headroom above for the current point's value and marker, and a
    /// little room below, so labels never run into the title. A nearly flat line keeps a
    /// minimum span instead of stretching small differences across the whole height.
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)

        guard let low = values.min(), let high = values.max() else {
            return 0...1
        }

        let minimumSpan = 10.0
        let span = max(high - low, minimumSpan)
        let middle = (low + high) / 2

        return (middle - span / 2 - span * 0.15)...(middle + span / 2 + span * 0.35)
    }

    /// Only the first, last and highlighted sessions name their date, so up to ten points never
    /// crowd the axis with labels; every point keeps its date for VoiceOver.
    private func showsDate(_ point: TMTrendPoint) -> Bool {
        point.highlight != .none
            || point.id == points.first?.id
            || point.id == points.last?.id
    }

    @ViewBuilder
    private func annotation(_ point: TMTrendPoint) -> some View {
        switch point.highlight {
        case .none:
            EmptyView()
        case .baseline:
            if let marker = point.marker {
                Text(marker)
                    .typography(.caption, weight: .semiBold)
                    .foregroundStyle(TherapyPalette.ink)
            }
        case .current:
            VStack(spacing: 0) {
                Text(verbatim: "\(Int(point.value.rounded()))\(unit)")
                    .typography(.subheadline, weight: .bold)

                if let marker = point.marker {
                    Text(marker)
                        .typography(.caption, weight: .semiBold)
                }
            }
            .foregroundStyle(TherapyPalette.ink)
        }
    }

    private func color(_ highlight: TMTrendPoint.Highlight) -> Color {
        switch highlight {
        case .none:
            return TherapyPalette.planTrack
        case .baseline:
            return TherapyPalette.guidanceBlue
        case .current:
            return TherapyPalette.brand
        }
    }

    private func symbolSize(_ highlight: TMTrendPoint.Highlight) -> CGFloat {
        switch highlight {
        case .none:
            return 40
        case .baseline:
            return 140
        case .current:
            return 260
        }
    }
}

#if DEBUG
#Preview("Trend chart") {
    let calendar = Calendar.current
    let values: [Double] = [84, 90, 88, 97, 104, 112]
    let points = values.enumerated().map { index, value in
        TMTrendPoint(
            id: index,
            date: calendar.date(byAdding: .day, value: (index - values.count) * 3, to: .now) ?? .now,
            value: value,
            highlight: index == 0 ? .baseline : (index == values.count - 1 ? .current : .none),
            marker: index == 0 ? "exerciseDetail.legend.firstSession" : (index == values.count - 1 ? "exerciseDetail.legend.now" : nil)
        )
    }

    TMTrendChart(title: "exerciseDetail.trend.title", points: points, unit: "°")
        .padding(32)
}
#endif
