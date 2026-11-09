//
//  DailyPlanNextView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The calm page between two exercises of today's plan: what comes next, a way to go on, and
/// a way to stop for today. After the last exercise it closes the day instead.
struct DailyPlanNextView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @State private var continuing = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer(minLength: 24)

            if let row = upcomingRow {
                upcoming(row)
            } else {
                dayComplete
            }

            Spacer(minLength: 24)

            actions

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 48)
        .foregroundStyle(TherapyPalette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
        .environment(\.colorScheme, .light)
        .interactiveDismissDisabled()
    }

    private var upcomingRow: DailyPlanRow? {
        guard let index = dependencies.dailyPlan.upcomingIndex else {
            return nil
        }

        return dependencies.dailyPlan.rows(in: dependencies)[index]
    }

    // MARK: - Content

    private func upcoming(_ row: DailyPlanRow) -> some View {
        HStack(spacing: 56) {
            TherapyArtwork(name: row.item.artwork, fallback: row.item.fallbackArtwork)
                .frame(width: 180, height: 280)

            VStack(alignment: .leading, spacing: 20) {
                Text("plan.next")
                    .typography(size: 26, weight: .regular, relativeTo: .title3)
                    .foregroundStyle(TherapyPalette.muted)

                Text(LocalizedStringKey(row.titleKey))
                    .typography(size: 52, weight: .bold, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(row.details.indices, id: \.self) { index in
                        detailLine(HomeView.planDetail(row.details[index]))
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailLine(_ detail: TherapyPlanDetail) -> some View {
        HStack(spacing: 14) {
            Image(systemName: detail.symbol)
                .frame(width: 30)
            Text(detail.text)
        }
        .typography(size: 26, weight: .regular, relativeTo: .title3)
    }

    private var dayComplete: some View {
        VStack(spacing: 20) {
            TherapyCompletionMark()

            Text("plan.dayComplete")
                .typography(size: 52, weight: .bold, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)

            Text("plan.dayCompleteMessage")
                .typography(size: 26, weight: .regular, relativeTo: .title3)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if upcomingRow != nil {
            VStack(spacing: 16) {
                TherapyButton(
                    title: "plan.nextContinue",
                    symbol: "play.fill",
                    disabled: continuing,
                    prominent: true
                ) {
                    continueToNext()
                }

                TherapyTextButton(title: "plan.finishToday") {
                    dependencies.dailyPlan.end(router: router)
                }
            }
        } else {
            TherapyButton(title: "plan.backHome", symbol: "house.fill", prominent: true) {
                dependencies.dailyPlan.end(router: router)
            }
        }
    }

    private func continueToNext() {
        continuing = true
        Task {
            await dependencies.dailyPlan.continueToNext(dependencies: dependencies, router: router)
        }
    }
}
