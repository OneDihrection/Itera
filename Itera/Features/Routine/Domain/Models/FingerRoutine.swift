//
//  FingerRoutine.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

typealias TrainingSide = HandSide

extension HandSide {
    var title: String { "side." + rawValue }
}

enum FingerExercise: String, CaseIterable, Identifiable {
    case fullFist, hookFist, opposition, spreading, extensionSequence, forearmRotation
    var id: String { rawValue }
    var title: String { "exercise." + rawValue }
    var detail: String { "detail." + rawValue }
    /// Localization keys for the numbered instructions shown before starting.
    var steps: [String] {
        (1...stepCount).map { "steps." + rawValue + "." + String($0) }
    }
    private var stepCount: Int { self == .opposition ? 5 : 4 }
    var symbol: String {
        switch self {
        case .fullFist: return "hand.raised.fill"
        case .hookFist: return "hand.point.up.left.fill"
        case .opposition: return "hand.pinch.fill"
        case .spreading: return "hand.raised.fingers.spread.fill"
        case .extensionSequence: return "hand.draw.fill"
        case .forearmRotation: return "arrow.triangle.2.circlepath"
        }
    }
    var isSequential: Bool { self == .opposition || self == .extensionSequence }
    var category: ExerciseCategory { self == .forearmRotation ? .forearm : .fingers }
    /// Sweeping the whole movement to measure a range is currently unused: every exercise,
    /// forearm rotation included, calibrates by holding a start pose and then a target pose.
    var calibratesRange: Bool { false }
    /// The static hand picture in the asset catalog, named `hand-<exercise>`.
    var artwork: String { "hand-" + rawValue }
}

/// A group of exercises that shares the finger-session flow but has its own plan, settings,
/// and saved-for-later session.
enum ExerciseCategory: String, CaseIterable, Identifiable, Hashable {
    case fingers, forearm
    var id: String { rawValue }
    var title: String { self == .fingers ? "plan.fingerTitle" : "exercise.forearmRotation" }
    var artwork: String { self == .fingers ? "hand-hero" : "hand-forearmRotation" }
    var exercises: [FingerExercise] {
        FingerExercise.allCases.filter { $0.category == self }
    }
}

struct FingerRoutine: Equatable {
    var category: ExerciseCategory = .fingers
    var side: TrainingSide = .left
    var sets = 2
    var repetitions = 5
    var restSeconds = 20
    var voiceControl = false
    var ambientSound = false
    /// Runs just this exercise of the category, as a daily-plan item does; `nil` runs them all.
    /// Not part of the saved settings: it is set for one session only.
    var only: FingerExercise?

    var exercises: [FingerExercise] {
        guard let only, only.category == category else {
            return category.exercises
        }

        return [only]
    }
}
