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

    /// Floats the exercise's detail panel over the day.
    func open(_ exercise: PracticedExercise)
}

/// "Perkembangan latihanmu": one day's practised exercises. It reads that day's exercises from
/// the Progress tab's loaded history, so opening a day reads no files and a record deleted from
/// the detail panel leaves the page once that history refreshes. A card opens the exercise's
/// detail panel.
@MainActor
@Observable
final class PracticeDayViewModel: PracticeDayViewModelProtocol {
    let day: Date

    @ObservationIgnored private let history: any PracticeHistoryProviding
    @ObservationIgnored private let router: any HistoryRouterProtocol

    init(
        day: Date,
        history: any PracticeHistoryProviding,
        router: any HistoryRouterProtocol
    ) {
        self.day = day
        self.history = history
        self.router = router
    }

    /// Read through the observable history, so the page follows its refreshes.
    var exercises: [PracticedExercise] {
        history.practiceHistory.exercises(on: day)
    }

    func open(_ exercise: PracticedExercise) {
        router.showExerciseDetail(exercise, on: day)
    }
}
