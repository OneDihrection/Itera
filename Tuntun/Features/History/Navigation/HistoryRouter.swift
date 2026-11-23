//
//  HistoryRouter.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

/// A page pushed onto the Progress tab's stack.
enum HistoryRoute: Hashable {
    case fingerReport(UUID)
    /// One arm-practice session with its key-repetition replays.
    case sessionReport(UUID)
    /// One day's practice ("Perkembangan latihanmu"), at the start of that day.
    case practiceDay(Date)
}

/// One exercise of one day, shown in the floating detail panel over the Progress stack.
struct ExerciseDetailRoute: Identifiable, Hashable {
    /// Start of the day the exercise was opened from.
    let day: Date
    let exercise: PracticedExercise

    var id: String {
        "\(day.timeIntervalSinceReferenceDate)-\(exercise.id)"
    }
}

@MainActor
protocol HistoryRouterProtocol: AnyObject {
    func showFingerReport(id: UUID)
    func showSessionReport(id: UUID)
    func showPracticeDay(_ day: Date)
    /// Floats the exercise's detail panel over the current page.
    func showExerciseDetail(_ exercise: PracticedExercise, on day: Date)
    func dismissExerciseDetail()
    func pop()
    func popToRoot()
}

/// Navigation for the Progress tab. It owns the tab's stack path and the floating exercise
/// detail panel; the reports list binds its `NavigationStack` and panel overlay to them, and
/// every page on that stack receives this router.
@MainActor
@Observable
final class HistoryRouter: HistoryRouterProtocol {
    var path: [HistoryRoute] = []
    var exerciseDetail: ExerciseDetailRoute?

    func showFingerReport(id: UUID) {
        path.append(.fingerReport(id))
    }

    func showSessionReport(id: UUID) {
        path.append(.sessionReport(id))
    }

    func showPracticeDay(_ day: Date) {
        path.append(.practiceDay(day))
    }

    func showExerciseDetail(_ exercise: PracticedExercise, on day: Date) {
        exerciseDetail = ExerciseDetailRoute(day: day, exercise: exercise)
    }

    func dismissExerciseDetail() {
        exerciseDetail = nil
    }

    func pop() {
        guard !path.isEmpty else {
            return
        }

        exerciseDetail = nil
        path.removeLast()
    }

    func popToRoot() {
        exerciseDetail = nil
        path.removeAll()
    }
}
