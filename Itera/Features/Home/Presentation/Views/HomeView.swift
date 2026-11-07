//
//  HomeView.swift
//  Itera
//
//  Created by dimaswisodewo on 29/10/2026.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(PracticePreferences.patientName) private var patientName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("home.greetingSubtitle")
                    .typography(size: 24, weight: .regular, relativeTo: .title3)
                    .foregroundStyle(TherapyPalette.muted)
                todayCard
                if let error = dependencies.home.errorKey {
                    TherapyError(key: error)
                    TherapyButton(title: "action.retry", secondary: true) {
                        Task { await dependencies.home.refresh() }
                    }
                }
                programs
            }
            // The system page margin keeps content aligned under the large navigation title.
            .scenePadding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas)
        .navigationTitle(greetingTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.presentSheet(.practicePreferences)
                } label: {
                    Label("cognitive.settings", systemImage: "gearshape")
                }
            }
        }
        .task { await dependencies.home.refresh() }
    }

    // MARK: - Greeting

    /// "Halo, Bu Yuli!" when a name is set in Settings, otherwise "Halo!".
    private var greetingTitle: Text {
        let name = patientName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return Text("home.hello")
        }

        return Text("home.greetingName \(name)")
    }

    // MARK: - Today

    private var todayCard: some View {
        let routine = dependencies.home.checkpoint?.routine ?? dependencies.home.routine
        let exercise = todayExercise
        let continuing = dependencies.home.checkpoint != nil

        return TherapyHeroCard(
            eyebrow: "home.todayExercise",
            title: LocalizedStringKey(exercise.title),
            detail: "home.setsReps \(routine.sets) \(routine.repetitions)",
            actionTitle: continuing ? "home.continueExercise" : "home.startExercise",
            actionSymbol: continuing ? "arrow.clockwise" : "play.fill"
        ) {
            startToday(exercise, continuing: continuing)
        }
    }

    /// The exercise a saved session will resume with, otherwise the first in the routine.
    private var todayExercise: FingerExercise {
        guard let checkpoint = dependencies.home.checkpoint else {
            return dependencies.home.routine.exercises.first ?? .fullFist
        }

        let exercises = checkpoint.routine.exercises
        let index = min(max(0, checkpoint.exerciseIndex), exercises.count - 1)
        return exercises[index]
    }

    private func startToday(_ exercise: FingerExercise, continuing: Bool) {
        guard continuing else {
            router.push(.exercisePreview(exercise))
            return
        }

        dependencies.prepareSession(continuing: true)
        router.presentFullScreenCover(.fingerSession)
    }

    // MARK: - Programs

    private var programs: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("home.programs")
                .typography(size: 24, weight: .semiBold, relativeTo: .title2)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: programColumns, alignment: .leading, spacing: 24) {
                TherapyProgramCard(
                    title: "home.program.finger",
                    detail: "home.setsReps \(dependencies.home.routine.sets) \(dependencies.home.routine.repetitions)",
                    artwork: "hand-hero",
                    mirrored: dependencies.home.routine.side == .left
                ) {
                    router.push(.fingerHome(.fingers))
                }
                TherapyProgramCard(
                    title: "home.armPractice",
                    detail: "home.program.armDetail",
                    artwork: "symbol:figure.arms.open"
                ) {
                    router.push(.therapyOverview(.arm))
                }
                TherapyProgramCard(
                    title: "balance.title",
                    detail: "home.program.balanceDetail",
                    artwork: "symbol:figure.stand"
                ) {
                    router.push(.balanceOverview(.crossMidline))
                }
                TherapyProgramCard(
                    title: "exercise.forearmRotation",
                    detail: "home.viewShort",
                    artwork: "hand-forearmRotation",
                    mirrored: dependencies.homeModel(for: .forearm).routine.side == .left
                ) {
                    router.push(.fingerHome(.forearm))
                }
                TherapyProgramCard(title: "home.trunkPractice", detail: "home.viewShort", artwork: "symbol:figure.seated.side") {
                    router.push(.therapyOverview(.trunk))
                }
                TherapyProgramCard(title: "rotation.category", detail: "home.viewShort", artwork: "symbol:arrow.triangle.2.circlepath") {
                    router.push(.armRotationHome)
                }
                TherapyProgramCard(title: "task.category", detail: "home.viewShort", artwork: "symbol:square.stack.3d.up") {
                    router.push(.therapyOverview(.taskOriented))
                }
            }
        }
    }

    private var programColumns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: count)
    }
}
