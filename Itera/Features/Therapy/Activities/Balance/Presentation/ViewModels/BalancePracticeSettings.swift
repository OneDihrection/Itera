//
//  BalancePracticeSettings.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import Foundation

/// The settings a Balancing-screen exercise remembers in UserDefaults, read in one place so
/// the overview page and the daily plan always start a session with the same values.
struct BalancePracticeSettings: Hashable {
    static let defaultRepetitions = 6
    static let defaultHoldSeconds = 10
    static let defaultArmSelection = BalanceArmSelection.both
    static let defaultSets = 1
    static let defaultRestSeconds = 15
    static let setsRange = 1...5
    static let restRange = 5...120

    var repetitions: Int
    var holdSeconds: Int
    var armSelection: BalanceArmSelection
    /// Sets of `repetitions` each; the calibration is kept between sets.
    var sets: Int
    /// Rest before each later set.
    var restSeconds: Int

    /// Reads what the exercise's overview page last saved, falling back to its defaults.
    init(exercise: BalanceExercise, defaults: UserDefaults = .standard) {
        let repetitionsKey = exercise.storageKey("repetitions")
        let holdKey = exercise.storageKey("holdSeconds")
        let armKey = exercise.storageKey("armSelection")

        repetitions = defaults.object(forKey: repetitionsKey) as? Int ?? Self.defaultRepetitions
        holdSeconds = defaults.object(forKey: holdKey) as? Int ?? Self.defaultHoldSeconds
        armSelection = defaults.string(forKey: armKey).flatMap(BalanceArmSelection.init(rawValue:))
            ?? Self.defaultArmSelection

        let savedSets = defaults.object(forKey: exercise.storageKey("sets")) as? Int ?? Self.defaultSets
        sets = min(Self.setsRange.upperBound, max(Self.setsRange.lowerBound, savedSets))

        let savedRest = defaults.object(forKey: exercise.storageKey("restSeconds")) as? Int ?? Self.defaultRestSeconds
        restSeconds = min(Self.restRange.upperBound, max(Self.restRange.lowerBound, savedRest))
    }
}
