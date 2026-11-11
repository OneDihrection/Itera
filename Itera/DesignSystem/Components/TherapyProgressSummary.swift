//
//  TherapyProgressSummary.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

// MARK: - Week summary

struct TherapyProgressDay: Identifiable {
    enum Status {
        case empty, partial, done

        var symbol: String {
            switch self {
            case .empty: return "minus"
            case .partial: return "pause.fill"
            case .done: return "checkmark"
            }
        }

        var tint: Color {
            switch self {
            case .empty: return .gray
            case .partial: return TherapyPalette.progressSoftBar
            case .done: return TherapyPalette.brand
            }
        }
    }

    let id: Date
    let label: String
    let caption: LocalizedStringKey
    let status: Status
}

/// A weekly headline and a seven-day strip. Callers supply the labels and states.
struct TMTherapyWeekSummary<Highlight: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let days: [TherapyProgressDay]
    @ViewBuilder let highlight: Highlight

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(title)
                    .typography(size: 36, weight: .bold, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .typography(size: 22, weight: .medium, relativeTo: .title3)
                highlight.padding(.top, 16)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(TherapyPalette.onBrand)
            .padding(26)
            .frame(maxWidth: .infinity)
            .background(TherapyPalette.brand, in: RoundedRectangle(cornerRadius: 26))

            ViewThatFits(in: .horizontal) {
                dayRow
                ScrollView(.horizontal) {
                    dayRow
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(TherapyPalette.progressPanel, in: RoundedRectangle(cornerRadius: 26))
    }

    private var dayRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(days) { day in
                VStack(spacing: 10) {
                    Text(verbatim: day.label)
                        .typography(size: 18, weight: .semiBold, relativeTo: .headline)
                    Image(systemName: day.status.symbol)
                        .typography(size: 14, weight: .bold)
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                        .background(day.status.tint, in: Circle())
                        .accessibilityHidden(true)
                    Text(day.caption)
                        .typography(size: 17, weight: .medium, relativeTo: .subheadline)
                        .foregroundStyle(day.status == .empty ? TherapyPalette.muted : TherapyPalette.warning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 96)
                }
                .frame(minWidth: 78, maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(18)
        .frame(maxWidth: .infinity)
    }
}

struct TMTherapyProgressSessionCard: View {
    let date: Date
    let completed: Int
    let planned: Int
    let minutes: Int
    let repetitions: Int
    var centeredDate = false

    var body: some View {
        VStack(spacing: 22) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .typography(.headline)
                .foregroundStyle(TherapyPalette.muted)
                .frame(maxWidth: .infinity, alignment: centeredDate ? .center : .leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    exercises
                    Divider().frame(height: 64)
                    duration
                    Divider().frame(height: 64)
                    repetitionsMetric
                }

                VStack(spacing: 18) {
                    exercises
                    duration
                    repetitionsMetric
                }
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background(TherapyPalette.progressPanel, in: RoundedRectangle(cornerRadius: 24))
        .foregroundStyle(TherapyPalette.ink)
    }

    private var exercises: some View {
        TMTherapyProgressMetric(icon: "waveform.path", value: Text("progress.exercisesDone \(completed) \(planned)"), title: "progress.exerciseUnit")
    }

    private var duration: some View {
        TMTherapyProgressMetric(icon: "clock", value: Text(minutes, format: .number), title: "progress.minuteUnit")
    }

    private var repetitionsMetric: some View {
        TMTherapyProgressMetric(icon: "repeat", value: Text(repetitions, format: .number), title: "progress.repetitionUnit")
    }
}

/// A terracotta icon tile over a large value and a muted unit, as used across the Progress pages.
struct TMTherapyProgressMetric: View {
    let icon: String
    let value: Text
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(TherapyPalette.brand)
                .frame(width: 38, height: 38)
                .background(TherapyPalette.progressSoftBar.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(TherapyPalette.progressSoftBar) }
                .accessibilityHidden(true)
            value.typography(.title2)
            Text(title).typography(.subheadline).foregroundStyle(TherapyPalette.muted)
        }
        .frame(minWidth: 124, maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct TMTherapyWeeklyRepetitionChart: View {
    struct Bar: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let repetitions: Int
    }

    let headline: LocalizedStringKey
    let bars: [Bar]

    var body: some View {
        let maximum = max(1, bars.map(\.repetitions).max() ?? 0)

        VStack(spacing: 24) {
            Text(headline).typography(.title3).multilineTextAlignment(.center)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(bars) { bar in
                    VStack(spacing: 8) {
                        VStack(spacing: 8) {
                            Text(bar.repetitions, format: .number).typography(.headline)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(bar.id == 0 || bar.id == bars.count - 1
                                      ? TherapyPalette.progressSoftBar : TherapyPalette.progressBar)
                                .frame(width: 42, height: bar.repetitions == 0
                                       ? 0 : max(4, 122 * CGFloat(bar.repetitions) / CGFloat(maximum)))
                        }
                        .frame(height: 164, alignment: .bottom)
                        Text(bar.title)
                            .typography(.footnote)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 42, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(bar.title))
                    .accessibilityValue(Text("progress.chartValue \(bar.repetitions)"))
                }
            }
            Text("progress.currentWeekNote").typography(.subheadline).foregroundStyle(TherapyPalette.muted)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background(TherapyPalette.progressPanel, in: RoundedRectangle(cornerRadius: 26))
    }
}
