//
//  DailyPlanCard.swift
//  Tuntun
//
//  Created by Gracia A on 21/11/2026.
//

import SwiftUI

/// Visual state for one reusable daily-plan row.
enum TMDailyPlanCardState: Equatable {
    case completed
    case current(step: Int)
    case upcoming(step: Int)

    var isAvailable: Bool {
        switch self {
        case .completed, .current:
            return true
        case .upcoming:
            return false
        }
    }
}

/// One exercise in the Beranda timeline, including its marker, metrics and illustration tile.
struct TMDailyPlanCard: View {
    let title: LocalizedStringKey
    let sets: Int
    let repetitions: Int
    let duration: ClosedRange<Int>
    let state: TMDailyPlanCardState
    let isLast: Bool
    var isInteractionEnabled = true
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 58) {
            timeline

            card
        }
        .accessibilityElement(children: .combine)
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            marker

            if !isLast {
                Rectangle()
                    .fill(connectorColor)
                    .frame(width: 4, height: 120)
            }
        }
        .frame(width: 64)
    }

    @ViewBuilder
    private var marker: some View {
        switch state {
        case .completed:
            Circle()
                .fill(TherapyPalette.planMarker)
                .overlay {
                    Image(systemName: "checkmark")
                        .typography(size: 28, weight: .bold, relativeTo: .title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)

        case .current(let step):
            stepMarker(step: step, dashed: true)

        case .upcoming(let step):
            stepMarker(step: step, dashed: false)
        }
    }

    private func stepMarker(step: Int, dashed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(TherapyPalette.canvas)

            Circle()
                .strokeBorder(
                    dashed ? TherapyPalette.planMarker : TherapyPalette.actionMuted,
                    style: StrokeStyle(
                        lineWidth: 4,
                        lineCap: .round,
                        dash: dashed ? [6, 7] : []
                    )
                )

            Text(step, format: .number)
                .typography(size: 28, weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.planStepInk)
        }
        .frame(width: 64, height: 64)
    }

    private var card: some View {
        Button(action: action) {
            VStack(spacing: 35) {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .typography(size: 32, weight: .bold, relativeTo: .title2)
                            .tracking(0.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        metrics
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    RoundedRectangle(cornerRadius: 28)
                        .fill(tileColor)
                        .frame(width: 104, height: 104)
                        .accessibilityHidden(true)
                }
                .frame(height: 104)

                Rectangle()
                    .fill(TherapyPalette.planDivider)
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(contentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .disabled(!state.isAvailable || !isInteractionEnabled)
    }

    private var metrics: some View {
        HStack(spacing: 32) {
            metric(symbol: "list.bullet.below.rectangle", text: Text("plan.sets \(sets)"))
            metric(symbol: "arrow.trianglehead.2.counterclockwise.rotate.90", text: Text("plan.repetitions \(repetitions)"))
            metric(symbol: "clock", text: Text("home.dailyPlan.duration \(duration.lowerBound) \(duration.upperBound)"))
        }
        .typography(size: 24, weight: .regular, relativeTo: .body)
        .tracking(0.6)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private func metric(symbol: String, text: Text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            text
        }
    }

    private var connectorColor: Color {
        state == .completed ? TherapyPalette.planMarker : TherapyPalette.actionMuted
    }

    private var contentColor: Color {
        state.isAvailable ? TherapyPalette.brandInk : TherapyPalette.planMutedInk
    }

    private var tileColor: Color {
        state.isAvailable ? TherapyPalette.planAvailableTile : TherapyPalette.planDisabledTile
    }
}
