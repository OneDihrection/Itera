//
//  ArmRotationHomeView.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import SwiftUI

/// The Arm Rotation category: one row per rotation, each opening the Balancing-style setup screen.
struct ArmRotationHomeView: View {
    @Environment(NavigationRouter.self) private var router

    private let exercises: [BalanceExercise] = [.internalRotation, .externalRotation]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TherapyArtworkPanel(
                    title: "rotation.category",
                    subtitle: "",
                    artwork: "symbol:arrow.triangle.2.circlepath"
                )
                .clipShape(RoundedRectangle(cornerRadius: 30))
                Text("rotation.hubDetail")
                    .typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
                VStack(spacing: 12) {
                    ForEach(Array(exercises.enumerated()), id: \.element) { index, exercise in
                        TherapyExerciseRow(
                            title: exercise.localized("title"),
                            subtitle: "",
                            artwork: "symbol:arrow.triangle.2.circlepath",
                            color: TherapyPalette.illustrationBackground(at: index)
                        ) {
                            router.push(.balanceOverview(exercise))
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(TherapyPalette.cream)
        .navigationTitle("rotation.category")
    }
}
