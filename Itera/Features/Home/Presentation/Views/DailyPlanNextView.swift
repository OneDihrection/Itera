//
//  DailyPlanNextView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The page after the last exercise of today's plan.
struct DailyPlanNextView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        VStack(spacing: 40) {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                TherapyCompletionMark(tint: TherapyPalette.brand)

                Text("plan.dayComplete")
                    .typography(size: 52, weight: .bold, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)

                Text("plan.dayCompleteMessage")
                    .typography(size: 26, weight: .regular, relativeTo: .title3)
            }
            .multilineTextAlignment(.center)

            Spacer(minLength: 24)

            TherapyButton(title: "plan.backHome", symbol: "house.fill", prominent: true) {
                dependencies.dailyPlan.end(router: router)
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 48)
        .foregroundStyle(TherapyPalette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
        .environment(\.colorScheme, .light)
        .interactiveDismissDisabled()
    }
}
