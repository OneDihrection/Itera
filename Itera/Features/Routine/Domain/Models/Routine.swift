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

    var category: TherapyCategory { self == .sitToStand ? .trunk : .arm }
}

/// A group of therapy kinds that share the guided-session flow and have their own routine.
enum TherapyCategory: String, CaseIterable, Identifiable, Hashable {
    case arm, trunk
    var id: String { rawValue }
    var title: String { self == .arm ? "home.armPractice" : "home.trunkPractice" }
    var artwork: String { self == .arm ? "symbol:figure.arms.open" : "symbol:figure.stand" }
    var positioningKey: String { self == .arm ? "home.positioning" : "trunk.positioning" }
    var kinds: [TherapyKind] { TherapyKind.allCases.filter { $0.category == self } }
}

struct SessionActivity: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: TherapyKind
    let side: TherapySide
    let goal: Int

    /// Sit-to-stand has no trained side: the camera follows whichever leg it sees best.
    var hasSide: Bool { kind != .sitToStand }

    init(kind: TherapyKind, side: TherapySide, goal: Int) {
        id = UUID()
        self.kind = kind
        self.side = side
        self.goal = max(1, goal)
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

