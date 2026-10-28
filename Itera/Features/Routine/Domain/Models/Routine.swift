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
}

struct SessionActivity: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: TherapyKind
    let side: TherapySide
    let goal: Int

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

