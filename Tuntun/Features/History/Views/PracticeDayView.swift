//
//  PracticeDayView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

import SwiftUI

/// "Perkembangan latihanmu": the exercises practised on one day, one `TMHistoryCard` per session
/// of each, numbered in the order they were practised. A card opens the exercise's detail panel.
struct TMPracticeDayView<ViewModel: PracticeDayViewModelProtocol>: View {
    @State private var viewModel: ViewModel

    @Environment(\.locale) private var locale

    init(viewModel: ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.exercises.isEmpty {
                    emptyMessage
                } else {
                    cards
                }
            }
            .frame(maxWidth: 1180)
            .padding(.horizontal, 32)
            .padding(.top, 48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(TherapyPalette.progressCanvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleBlock
            }
        }
    }

    // MARK: - Sections

    /// Title and the day beneath it; iPadOS 17 has no navigation subtitle.
    /// The title is yellow at the product owner's request (2026-11-21), an exception to the
    /// "no yellow text" rule; the date is much smaller (`.subheadline` is 22 pt, almost the title).
    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text("practiceDay.title")
                .typography(size: 26, weight: .bold, relativeTo: .headline)
                .foregroundStyle(TherapyPalette.brand)

            Text(viewModel.day, format: .dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
                .typography(size: 16, weight: .regular, relativeTo: .footnote)
                .foregroundStyle(TherapyPalette.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var cards: some View {
        ForEach(Array(viewModel.exercises.enumerated()), id: \.element.id) { index, exercise in
            TMHistoryCard(
                title: LocalizedStringKey(exercise.titleKey),
                number: index + 1,
                artwork: ["sitToStand", "extensionSequence", "opposition", "crossMidline", "internalRotation", "hookFist", "forearmRotation", "fullFist", "spreading", "externalRotation", "directionalReach", "shoulderFlexion", "armRaise", "elbowBend", "foldTowel"].contains(exercise.exerciseID)
                    ? "exercise-card-" + exercise.exerciseID
                    : nil
            ) {
                viewModel.open(exercise)
            }
        }
    }

    private var emptyMessage: some View {
        Text("practiceDay.empty")
            .typography(.body)
            .foregroundStyle(TherapyPalette.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockPracticeDayViewModel: PracticeDayViewModelProtocol {
    let day = Calendar.current.startOfDay(for: .now)
    let exercises: [PracticedExercise]

    init(exercises: [PracticedExercise]) {
        self.exercises = exercises
    }

    func open(_ exercise: PracticedExercise) {}
}

private let previewExercises: [PracticedExercise] = [
    "opposition", "armRaise", "fullFist", "hookFist", "spreading", "extensionSequence",
    "forearmRotation", "elbowBend", "directionalReach", "crossMidline", "sitToStand", "foldTowel",
].map { id in
    PracticedExercise(
        exerciseID: id,
        titleKey: PracticeHistory.titleKey(for: id),
        report: .session(UUID())
    )
}

#Preview("Practice day") {
    NavigationStack {
        TMPracticeDayView(viewModel: MockPracticeDayViewModel(exercises: previewExercises))
    }
}

#Preview("Practice day, empty") {
    NavigationStack {
        TMPracticeDayView(viewModel: MockPracticeDayViewModel(exercises: []))
    }
}
#endif
