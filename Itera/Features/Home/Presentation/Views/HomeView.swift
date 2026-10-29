//
//  HomeView.swift
//  Itera
//
//  Created by dimaswisodewo on 29/10/2026.
//

import SwiftUI

struct HomeView: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("home.welcomeShort").typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
                Text("home.chooseTherapy").typography(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 28))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 28))
                layout {
                    category(title: "plan.fingerTitle", artwork: "hand-hero", route: .fingerHome)
                    category(title: "home.armPractice", artwork: "symbol:figure.arms.open", route: .therapyOverview)
                }
            }
            .padding(28)
        }
        .background(TherapyPalette.cream)
        .navigationTitle("Itera")
    }

    private func category(title: LocalizedStringKey, artwork: String, route: AppRoute) -> some View {
        VStack(spacing: 0) {
            TherapyArtworkPanel(title: title, subtitle: "", artwork: artwork)
            TherapyButton(title: "home.viewShort", symbol: "arrow.right") {
                router.push(route)
            }
            .padding(24)
        }
        .background(TherapyPalette.hero)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .frame(maxWidth: .infinity)
    }
}
