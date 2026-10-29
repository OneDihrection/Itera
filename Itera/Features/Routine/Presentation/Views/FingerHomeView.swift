//
//  FingerHomeView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerHomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heading
                if let error = dependencies.home.errorKey {
                    TherapyError(key: error)
                    TherapyButton(title: "action.retry", secondary: true) {
                        Task { await dependencies.home.refresh() }
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
            await dependencies.home.refresh()
            await dependencies.progress.refresh()
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
            VStack(alignment: .trailing, spacing: 8) {
                Label {
                    Text(dependencies.progress.progress.currentStreak, format: .number)
                    Text("progress.streakDays")
                } icon: {
                    Image(systemName: "flame.fill")
                }
                .typography(.headline).foregroundStyle(TherapyPalette.primary)
                Text(Date(), format: .dateTime.day().month(.abbreviated))
                    .typography(.body).foregroundStyle(TherapyPalette.muted)
            }
        }
        .foregroundStyle(TherapyPalette.ink)
    }

    private var featuredPlan: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 0) {
                TherapyArtworkPanel(
                    title: "plan.fingerTitle", subtitle: dependencies.home.movementSummary,
                    artwork: "hand-hero", mirrored: dependencies.home.routine.side == .left
                )
                VStack(alignment: .leading, spacing: 20) {
                    Text(verbatim: dependencies.home.repetitionSummary)
                        .typography(.body).foregroundStyle(TherapyPalette.pastelInk)
                    TherapyButton(title: "home.viewShort", symbol: "play.fill") { router.push(.plan) }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
                .background(TherapyPalette.hero)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30))

            TherapyButton(title: "home.armPractice", symbol: "figure.strengthtraining.traditional", secondary: true) {
                router.push(.therapyOverview)
            }

            if dependencies.home.checkpoint != nil {
                TherapyButton(title: "home.continueShort", symbol: "arrow.clockwise", secondary: true) {
                    dependencies.prepareSession(continuing: true)
                    router.presentFullScreenCover(.fingerSession)
                }
            }
        }
    }

    private var exerciseList: some View {
        VStack(spacing: 12) {
            ForEach(Array(FingerExercise.allCases.enumerated()), id: \.element) { index, exercise in
                TherapyExerciseRow(
                    title: LocalizedStringKey(exercise.title),
                    subtitle: dependencies.home.repetitionSummary,
                    artwork: "hand-" + exercise.rawValue,
                    color: TherapyPalette.illustrationBackground(at: index),
                    mirrored: dependencies.home.routine.side == .left
                ) {
                    router.presentSheet(.exercisePreview(exercise))
                }
            }
        }
    }
}
