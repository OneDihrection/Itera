//
//  RoutineConfiguration.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum RoutineSides: String, Codable, CaseIterable {
    case left, right, both
}

struct RoutineExercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: TherapyKind
    var sides: RoutineSides = .both
    var firstSide: TherapySide = .left
    var leftGoal = 5
    var rightGoal = 5
    var rounds = 1

    var activities: [SessionActivity] {
        let selected: [TherapySide]
        switch sides {
        case .left: selected = [.left]
        case .right: selected = [.right]
        case .both: selected = firstSide == .left ? [.left, .right] : [.right, .left]
        }
        return selected.map { side in
            SessionActivity(
                kind: kind, side: side,
                goal: kind == .armRaise || kind == .elbowBend
                    ? (side == .left ? leftGoal : rightGoal) : rounds
            )
        }
    }
}

struct RoutineConfiguration: Identifiable, Codable, Equatable {
    var id = UUID()
    var exercises: [RoutineExercise] = []
    var restSeconds = 15
    var practiceSeconds = 60

    var snapshot: Routine {
        Routine(activities: exercises.flatMap(\.activities), restSeconds: Double(restSeconds), practiceSeconds: Double(practiceSeconds), id: id)
    }
}
