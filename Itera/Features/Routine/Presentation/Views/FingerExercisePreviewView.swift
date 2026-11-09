//
//  FingerExercisePreviewView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

/// The page shown before starting: a looping demonstration, numbered steps and the targets.
struct TMFingerExercisePreviewView: View {
    let exercise: FingerExercise
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var starting = false

    private var home: FingerHomeViewModel { dependencies.homeModel(for: exercise.category) }

    var body: some View {
        content
            .scenePadding(.horizontal)
            .padding(.vertical, 16)
            .foregroundStyle(TherapyPalette.ink)
            .background(TherapyPalette.canvas)
            .navigationTitle(LocalizedStringKey(exercise.title))
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            ScrollView {
                VStack(spacing: 28) {
                    demonstration.frame(height: 420)
                    details
                }
            }
        } else {
            HStack(alignment: .top, spacing: 44) {
                demonstration
                ScrollView {
                    details
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Sections

    private var demonstration: some View {
        TMTherapyMediaPanel {
            TMFingerExampleView(
                exercise: exercise,
                phase: .demonstration,
                returning: false,
                finger: 0,
                side: home.routine.side,
                paused: false
            )
            .background(TherapyPalette.mediaBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityLabel("session.example")
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 420)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("exercise.instructions")
                .typography(size: 24, weight: .semiBold, relativeTo: .title2)
                .accessibilityAddTraits(.isHeader)
            TMTherapyNumberedSteps(steps: exercise.steps.map { LocalizedStringKey($0) })

            Text("exercise.target")
                .typography(size: 24, weight: .semiBold, relativeTo: .title2)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 12)
            targets

            if let error = home.errorKey {
                TMTherapyError(key: error)
            }

            TMTherapyButton(title: "exercise.start", disabled: starting, pill: true, action: start)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targets: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 16))
            : AnyLayout(HStackLayout(spacing: 16))

        return layout {
            TMTherapyTargetTile(value: home.routine.sets, unit: "exercise.setsUnit")
            TMTherapyTargetTile(
                value: home.routine.repetitions,
                unit: "exercise.repetitionsUnit",
                suffix: "x"
            )
        }
    }

    // MARK: - Actions

    /// Starts today's routine. The routine always runs its exercises in their saved order.
    private func start() {
        guard !starting else {
            return
        }

        starting = true

        Task {
            defer { starting = false }

            guard await home.saveRoutine() else {
                return
            }

            dependencies.prepareSession(category: exercise.category)
            router.presentFullScreenCover(.fingerSession)
        }
    }
}
