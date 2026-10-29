//
//  FingerExercisePreviewView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerExercisePreviewView: View {
    let exercise: FingerExercise
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @State private var playing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                FingerDemonstrationView(
                    exercise: exercise, phase: .demonstration,
                    returning: false, finger: 0,
                    side: dependencies.home.routine.side, paused: !playing
                )
                .frame(height: 360)
                .frame(maxWidth: 360)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                Text(LocalizedStringKey(exercise.detail)).typography(.title2)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                TherapyButton(
                    title: playing ? "action.pause" : "exercise.playExample",
                    symbol: playing ? "pause.fill" : "play.fill"
                ) { playing.toggle() }
                Text(LocalizedStringKey(dependencies.home.routine.side.title))
                    .typography(.body).foregroundStyle(TherapyPalette.muted)
            }
            .padding(28)
        }
        .background(TherapyPalette.cream)
        .navigationTitle(LocalizedStringKey(exercise.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") { router.dismissSheet() }
                    .typography(.headline).frame(minHeight: 44)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
