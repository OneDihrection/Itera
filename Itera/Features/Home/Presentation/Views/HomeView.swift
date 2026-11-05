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
                therapyCategories
            }
            .padding(28)
        }
        .background(TherapyPalette.cream)
        .navigationTitle("Itera")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.presentSheet(.practicePreferences)
                } label: {
                    Label("cognitive.settings", systemImage: "slider.horizontal.3")
                        .typography(.headline)
                        .frame(minHeight: 64)
                }
            }
        }
    }

    @ViewBuilder
    private var therapyCategories: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 28) {
                fingerCategory
                armCategory
                balanceCategory
            }
        } else {
            VStack(spacing: 28) {
                HStack(alignment: .top, spacing: 28) {
                    fingerCategory
                    armCategory
                }
                balanceCategory
            }
        }
    }

    private var fingerCategory: some View {
        category(title: "plan.fingerTitle", artwork: "hand-hero", route: .fingerHome)
    }

    private var armCategory: some View {
        category(
            title: "home.armPractice",
            artwork: "symbol:figure.arms.open",
            route: .therapyOverview
        )
    }

    private var balanceCategory: some View {
        category(
            title: "balance.title",
            artwork: "symbol:figure.stand",
            route: .balanceOverview
        )
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
