//
//  Routine.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum TherapySide: String, Codable {
    case left
    case right
}

enum TherapyKind: String, Codable, CaseIterable {
    case armRaise
    case elbowBend
    case directionalReach
    case cup
    case sitToStand
    case foldTowel

    var category: TherapyCategory {
        switch self {
        case .foldTowel: return .taskOriented
        case .sitToStand: return .trunk
        case .armRaise, .elbowBend, .directionalReach, .cup: return .arm
        }
    }
}

/// A group of therapy kinds that share the guided-session flow and have their own routine.
enum TherapyCategory: String, CaseIterable, Identifiable, Hashable {
    case arm, trunk, taskOriented
    var id: String { rawValue }
    var title: String {
        switch self {
        case .arm: return "home.armPractice"
        case .trunk: return "home.trunkPractice"
        case .taskOriented: return "task.category"
        }
    }

    var artwork: String {
        switch self {
        case .arm: return "symbol:figure.arms.open"
        case .trunk: return "symbol:figure.stand"
        case .taskOriented: return "symbol:square.stack.3d.up"
        }
    }

    var positioningKey: String {
        switch self {
        case .arm: return "home.positioning"
        case .trunk: return "trunk.positioning"
        case .taskOriented: return "towel.positioning"
        }
    }

    var kinds: [TherapyKind] { TherapyKind.allCases.filter { $0.category == self } }
}

struct SessionActivity: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: TherapyKind
    let side: TherapySide
    let goal: Int
    var sets: Int = 1

    enum CodingKeys: String, CodingKey { case id, kind, side, goal, sets }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(TherapyKind.self, forKey: .kind)
        side = try values.decode(TherapySide.self, forKey: .side)
        goal = try values.decode(Int.self, forKey: .goal)
        sets = try values.decodeIfPresent(Int.self, forKey: .sets) ?? 1
        guard (1...5).contains(sets), kind != .sitToStand || sets == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .sets, in: values, debugDescription: "Invalid set count")
        }
    }

    /// Sit-to-stand has no trained side: the camera follows whichever leg it sees best.
    var hasSide: Bool { kind != .sitToStand }

    init(kind: TherapyKind, side: TherapySide, goal: Int, sets: Int = 1) {
        id = UUID()
        self.kind = kind
        self.side = side
        self.goal = max(1, goal)
        self.sets = kind == .sitToStand ? 1 : min(5, max(1, sets))
    }
}

struct Routine: Codable, Equatable {
    var id: UUID?
    let activities: [SessionActivity]
    let restSeconds: Double
    var practiceSeconds: Double = 60

    enum CodingKeys: String, CodingKey { case id, activities, restSeconds, practiceSeconds }

    init(activities: [SessionActivity], restSeconds: Double, practiceSeconds: Double = 60, id: UUID? = nil) {
        self.id = id
        self.activities = activities
        self.restSeconds = restSeconds
        self.practiceSeconds = practiceSeconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id)
        activities = try values.decode([SessionActivity].self, forKey: .activities)
        restSeconds = try values.decode(Double.self, forKey: .restSeconds)
        practiceSeconds = try values.decodeIfPresent(Double.self, forKey: .practiceSeconds) ?? 60
    }

    static func demo() -> Routine {
        Routine(
            activities: [
                SessionActivity(kind: .armRaise, side: .left, goal: 5),
                SessionActivity(kind: .armRaise, side: .right, goal: 5),
                SessionActivity(kind: .elbowBend, side: .left, goal: 5),
                SessionActivity(kind: .elbowBend, side: .right, goal: 5),
                SessionActivity(kind: .directionalReach, side: .left, goal: 1),
            ],
            restSeconds: 15
        )
    }
}

