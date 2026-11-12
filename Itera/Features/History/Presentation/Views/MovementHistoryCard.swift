//
//  MovementHistoryCard.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import SwiftUI

/// One saved session with recorded movement (guided arm practice or a Balancing exercise) in
/// "Riwayat latihan": its date and outcome, each exercise's repetitions against the plan, and a
/// way into its movement report.
struct TMMovementHistoryCard: View {
    let summary: SessionSummary

    var body: some View {
        TMTherapyCard(color: TherapyPalette.canvas, outlined: true, padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(summary.startedAt, format: .dateTime.weekday(.wide).day().month(.abbreviated).year())
                        .typography(size: 24, weight: .semiBold, relativeTo: .headline)
                    Spacer(minLength: 12)
                    Label(outcomeTitle, systemImage: outcomeSymbol)
                        .typography(size: 20, weight: .medium, relativeTo: .subheadline)
                }

                ForEach(exercises) { exercise in
                    exerciseRow(exercise)
                }

                Divider()
                HStack {
                    Spacer()
                    Label("history.card.viewMovement", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .typography(size: 20, weight: .semiBold, relativeTo: .subheadline)
                        .foregroundStyle(TherapyPalette.brand)
                }
            }
            .foregroundStyle(TherapyPalette.ink)
            .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Exercises

    /// One configured exercise with every set's repetitions added together.
    private struct Exercise: Identifiable {
        let activity: SessionActivity
        let done: Int

        var id: UUID { activity.id }
        var planned: Int { activity.goal * activity.sets }
    }

    private var exercises: [Exercise] {
        summary.routine.activities
            .filter(\.kind.recordsMovement)
            .map { activity in
                Exercise(
                    activity: activity,
                    done: summary.results
                        .filter { $0.activity.id == activity.id }
                        .reduce(0) { $0 + $1.completedWork }
                )
            }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: exercise.activity.kind.symbolName)
                .accessibilityHidden(true)
            exercise.activity.reportTitle
                .typography(size: 22, weight: .semiBold, relativeTo: .headline)
            Spacer(minLength: 12)
            Text("history.card.repetitions \(exercise.done) \(exercise.planned)")
                .typography(size: 22, weight: .regular, relativeTo: .body)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Outcome

    private var totalDone: Int {
        exercises.reduce(0) { $0 + $1.done }
    }

    private var completed: Bool {
        !summary.stopped && summary.results.allSatisfy { $0.outcome == .completed }
    }

    private var outcomeSymbol: String {
        if completed { return "checkmark" }
        return totalDone > 0 ? "checkmark.square" : "minus.square"
    }

    private var outcomeTitle: LocalizedStringKey {
        if completed { return "progress.outcome.completed" }
        return totalDone > 0 ? "progress.partial" : "progress.notDone"
    }
}

/// Puts the icon after the title, for "View movement ›".
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}
