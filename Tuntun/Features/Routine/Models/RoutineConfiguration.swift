//
//  RoutineConfiguration.swift
//  Tuntun
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

    /// - Parameter sides: the exercise's sides; without one, `defaultSides(for:)`.
    init(kind: TherapyKind, sides: RoutineSides? = nil) {
        self.kind = kind
        self.sides = sides ?? Self.defaultSides(for: kind)
        if kind == .foldTowel {
            leftGoal = 1
            rightGoal = 1
        }
    }

    /// Elbow bend and directional reach start on the left arm, which their Indonesian 2026-11-24
    /// scripts are written for; every other exercise starts with both sides. A saved routine or a
    /// side chosen in Settings keeps its own.
    static func defaultSides(for kind: TherapyKind) -> RoutineSides {
        switch kind {
        case .elbowBend, .directionalReach:
            return .left
        default:
            return .both
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
    ///
    /// Both sides make one activity whose sides take turns after every repetition, as Balancing
    /// does; its goal counts the repetitions of both sides together.
    var activities: [SessionActivity] {
        switch sides {
        case .left:
            return [activity(side: .left, goal: goal(for: .left))]
        case .right:
            return [activity(side: .right, goal: goal(for: .right))]
        case .both:
            return [activity(side: firstSide, goal: goal(for: firstSide), alternatesSides: true)]
        }
    }

    private func goal(for side: TherapySide) -> Int {
        guard kind == .armRaise || kind == .elbowBend || kind == .foldTowel else {
            return rounds
        }

        return side == .left ? leftGoal : rightGoal
    }

    private func activity(side: TherapySide, goal: Int, alternatesSides: Bool = false) -> SessionActivity {
        SessionActivity(
            kind: kind,
            side: side,
            goal: goal,
            sets: sets,
            alternatesSides: alternatesSides
        )
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
