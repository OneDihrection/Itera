//
//  FingerHomeView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMFingerHomeView: View {
    let category: ExerciseCategory
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    private var home: FingerHomeViewModel { dependencies.homeModel(for: category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heading
                if let error = home.errorKey {
                    TMTherapyError(key: error)
                    TMTherapyButton(title: "action.retry", secondary: true) {
                        Task { await home.refresh() }
                    }
                }
                if typeSize.isAccessibilitySize {
                    featuredPlan
                    exerciseList
                } else {
                    HStack(alignment: .top, spacing: 28) {
                        featuredPlan.frame(maxWidth: .infinity)
                        exerciseList.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(28)
        }
        .background(TherapyPalette.cream)
        .navigationTitle("Itera")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await home.refresh()
        }
    }

    private var heading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("home.welcomeShort").typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
                Text("home.todayShort").typography(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Text(Date(), format: .dateTime.day().month(.abbreviated))
                .typography(.body)
                .foregroundStyle(TherapyPalette.muted)
        }
        .foregroundStyle(TherapyPalette.ink)
    }

    private var featuredPlan: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 0) {
                TMTherapyArtworkPanel(
                    title: LocalizedStringKey(category.title), subtitle: home.movementSummary,
                    artwork: category.artwork, mirrored: home.routine.side == .left
                )
                VStack(alignment: .leading, spacing: 20) {
                    Text(verbatim: home.repetitionSummary)
                        .typography(.body).foregroundStyle(TherapyPalette.pastelInk)
                    TMTherapyButton(title: "home.viewShort", symbol: "play.fill") { router.push(.plan(category)) }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
                .background(TherapyPalette.hero)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30))

            if home.checkpoint != nil {
                TMTherapyButton(title: "home.continueShort", symbol: "arrow.clockwise", secondary: true) {
                    dependencies.prepareSession(category: category, continuing: true)
                    router.presentFullScreenCover(.fingerSession)
                }
            }
        }
    }

    private var exerciseList: some View {
        VStack(spacing: 12) {
            ForEach(Array(category.exercises.enumerated()), id: \.element) { index, exercise in
                TMTherapyExerciseRow(
                    title: LocalizedStringKey(exercise.title),
                    subtitle: home.repetitionSummary,
                    artwork: exercise.artwork,
                    color: TherapyPalette.illustrationBackground(at: index),
                    mirrored: home.routine.side == .left
                ) {
                    router.push(.exercisePreview(exercise))
                }
            }
        }
    }
}
