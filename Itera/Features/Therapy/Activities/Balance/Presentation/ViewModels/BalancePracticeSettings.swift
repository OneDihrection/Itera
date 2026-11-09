//
//  BalancePracticeSettings.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import Foundation

/// The settings a Balancing-screen exercise remembers in UserDefaults, read in one place so
/// the overview page and the daily plan always start a session with the same values.
struct BalancePracticeSettings: Equatable {
    static let defaultRepetitions = 6
    static let defaultHoldSeconds = 10
    static let defaultArmSelection = BalanceArmSelection.both

    var repetitions: Int
    var holdSeconds: Int
    var armSelection: BalanceArmSelection

    /// Reads what the exercise's overview page last saved, falling back to its defaults.
    init(exercise: BalanceExercise, defaults: UserDefaults = .standard) {
        let repetitionsKey = exercise.storageKey("repetitions")
        let holdKey = exercise.storageKey("holdSeconds")
        let armKey = exercise.storageKey("armSelection")

        repetitions = defaults.object(forKey: repetitionsKey) as? Int ?? Self.defaultRepetitions
        holdSeconds = defaults.object(forKey: holdKey) as? Int ?? Self.defaultHoldSeconds
        armSelection = defaults.string(forKey: armKey).flatMap(BalanceArmSelection.init(rawValue:))
            ?? Self.defaultArmSelection
    }
}
