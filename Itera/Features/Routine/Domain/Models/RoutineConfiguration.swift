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
    var sets = 1

    enum CodingKeys: String, CodingKey {
        case id, kind, sides, firstSide, leftGoal, rightGoal, rounds, sets
    }

    init(kind: TherapyKind, sides: RoutineSides = .both) {
        self.kind = kind
        self.sides = sides
        if kind == .foldTowel {
            leftGoal = 1
            rightGoal = 1
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(TherapyKind.self, forKey: .kind)
        sides = try values.decode(RoutineSides.self, forKey: .sides)
        firstSide = try values.decode(TherapySide.self, forKey: .firstSide)
        leftGoal = try values.decode(Int.self, forKey: .leftGoal)
        rightGoal = try values.decode(Int.self, forKey: .rightGoal)
        rounds = try values.decode(Int.self, forKey: .rounds)
        sets = try values.decodeIfPresent(Int.self, forKey: .sets) ?? 1
        guard (1...5).contains(sets) else {
            throw DecodingError.dataCorruptedError(
                forKey: .sets, in: values, debugDescription: "Invalid set count")
        }
    }

    /// Repetition goals are per side for arm movements; sit-to-stand has no side and uses `leftGoal`
    /// as its one repetition goal so previously saved routines still decode.
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
                goal: kind == .armRaise || kind == .elbowBend || kind == .foldTowel
                    ? (side == .left ? leftGoal : rightGoal) : rounds,
                sets: sets
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
