//
//  TherapyProgressArtwork.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Charts
import SwiftUI

struct TherapyBadge: View {
    let symbol: String
    let value: String
    var earned = false
    var size: CGFloat = 90

    var body: some View {
        ZStack {
            Circle().fill(earned ? TherapyPalette.tertiary.gradient : TherapyPalette.subtleSurface.gradient)
            Circle().stroke(earned ? TherapyPalette.primary.opacity(0.45) : TherapyPalette.muted.opacity(0.25), lineWidth: 3)
                .padding(5)
            VStack(spacing: 4) {
                Image(systemName: earned ? symbol : "lock.fill")
                    .typography(size: size * 0.28, weight: .bold)
                if earned {
                    Text(verbatim: value).typography(size: size * 0.21, weight: .bold)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(earned ? TherapyPalette.primary : TherapyPalette.muted)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct TherapyChartPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

struct TherapyProgressChart: View {
    let title: LocalizedStringKey
    let points: [TherapyChartPoint]
    var line = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title).typography(.title2)
            Chart(points) { point in
                if line {
                    AreaMark(x: .value("chart.day", point.date, unit: .day), y: .value(title, point.value))
                        .foregroundStyle(TherapyPalette.primary.opacity(0.12))
                    LineMark(x: .value("chart.day", point.date, unit: .day), y: .value(title, point.value))
                        .foregroundStyle(TherapyPalette.primary)
                        .symbol(.circle)
                } else {
                    BarMark(x: .value("chart.day", point.date, unit: .day), y: .value(title, point.value))
                        .foregroundStyle(TherapyPalette.primary.gradient)
                        .cornerRadius(8)
                }
            }
            .chartYScale(domain: 0...max(1, (points.map(\.value).max() ?? 0) * 1.2))
            .chartXAxis {
                AxisMarks(values: points.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.weekday(.abbreviated)).typography(.caption)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self), line || number.rounded() == number {
                            Text(number, format: .number.precision(.fractionLength(0...1))).typography(.caption)
                        }
                    }
                }
            }
            .frame(height: 220)
            .accessibilityLabel(title)
            .accessibilityValue(Text(points.reduce(0) { $0 + $1.value }, format: .number.precision(.fractionLength(0...1))))
        }
        .padding(26)
        .background(TherapyPalette.surface, in: RoundedRectangle(cornerRadius: 28))
    }
}
