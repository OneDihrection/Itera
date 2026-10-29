//
//  FingerPlanView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerPlanView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if typeSize.isAccessibilitySize {
                    overview
                    sequence
                } else {
                    HStack(alignment: .top, spacing: 28) {
                        overview.frame(maxWidth: .infinity)
                        sequence.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(28)
        }
        .background(TherapyPalette.cream)
        .navigationTitle("plan.titleShort")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            TherapyArtworkPanel(
                title: "plan.fingerTitle", subtitle: dependencies.home.movementSummary,
                artwork: "hand-hero", mirrored: dependencies.home.routine.side == .left
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            HStack(spacing: 20) {
                TherapyMetric(title: "plan.setsShort", value: String(dependencies.home.routine.sets))
                TherapyMetric(title: "plan.repsShort", value: String(dependencies.home.routine.repetitions))
                TherapyMetric(title: "plan.restShort", value: String(dependencies.home.routine.restSeconds) + " s")
            }
            .padding(.horizontal, 8)
            HStack(spacing: 24) {
                Label(LocalizedStringKey(dependencies.home.routine.side.title), systemImage: "hand.raised")
                    .typography(.headline).foregroundStyle(TherapyPalette.green)
                Spacer()
                TherapyButton(title: "plan.editShort", symbol: "slider.horizontal.3", secondary: true) {
                    router.presentSheet(.routineSettings)
                }
                .frame(width: 170)
                .accessibilityLabel("plan.edit")
            }
            if let error = dependencies.home.errorKey {
                TherapyError(key: error)
            }
        }
    }

    private var sequence: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("plan.sequenceShort").typography(.title2)
                .foregroundStyle(TherapyPalette.ink).padding(.bottom, 4)
            ForEach(Array(FingerExercise.allCases.enumerated()), id: \.element) { index, exercise in
                TherapyExerciseRow(
                    title: LocalizedStringKey(exercise.title),
                    subtitle: dependencies.home.repetitionSummary,
                    artwork: "hand-" + exercise.rawValue,
                    color: TherapyPalette.illustrationBackground(at: index),
                    mirrored: dependencies.home.routine.side == .left, number: index + 1
                ) {
                    router.presentSheet(.exercisePreview(exercise))
                }
            }
        }
    }

    private var startBar: some View {
        VStack(spacing: 12) {
            Text("plan.comfortShort").typography(.footnote).foregroundStyle(TherapyPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            TherapyButton(title: "plan.startShort", symbol: "play.fill") {
                Task {
                    if await dependencies.home.saveRoutine() {
                        dependencies.prepareSession()
                        router.presentFullScreenCover(.fingerSession)
                    }
                }
            }
            .frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 28).padding(.vertical, 16)
        .background(.regularMaterial)
    }
}
