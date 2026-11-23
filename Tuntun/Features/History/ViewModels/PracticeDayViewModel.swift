//
//  PracticeDayViewModel.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

import Foundation
import Observation

@MainActor
protocol PracticeDayViewModelProtocol: AnyObject, Observable {
    /// Start of the day shown.
    var day: Date { get }
    /// Exercises practised that day, in the order first practised.
    var exercises: [PracticedExercise] { get }

    /// Opens the exercise's saved report; does nothing when it has none.
    func open(_ exercise: PracticedExercise)
}

/// "Perkembangan latihanmu": one day's practised exercises. It receives that day's exercises
/// from the Progress tab's loaded history, so opening a day reads no files.
@MainActor
@Observable
final class PracticeDayViewModel: PracticeDayViewModelProtocol {
    let day: Date
    let exercises: [PracticedExercise]

    @ObservationIgnored private let router: any HistoryRouterProtocol

    init(
        day: Date,
        exercises: [PracticedExercise],
        router: any HistoryRouterProtocol
    ) {
        self.day = day
        self.exercises = exercises
        self.router = router
    }

    func open(_ exercise: PracticedExercise) {
        guard let report = exercise.report else {
            return
        }

        switch report {
        case .finger(let id):
            router.showFingerReport(id: id)
        case .session(let id):
            router.showSessionReport(id: id)
        }
    }
}
