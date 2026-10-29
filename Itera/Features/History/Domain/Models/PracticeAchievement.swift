//
//  PracticeAchievement.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

enum AchievementFamily: String, CaseIterable {
    case repetitions, sets, days, streak, sessions, movement

    var title: String { "achievement.family." + rawValue }
    var symbol: String {
        switch self {
        case .repetitions: return "sparkles"
        case .sets: return "checkmark.seal.fill"
        case .days: return "sun.max.fill"
        case .streak: return "flame.fill"
        case .sessions: return "flag.checkered"
        case .movement: return "hand.wave.fill"
        }
    }
}

struct PracticeAchievement: Identifiable, Equatable {
    let family: AchievementFamily
    let target: Int
    var movement: FingerExercise? = nil
    var id: String { family.rawValue + "." + (movement?.rawValue ?? String(target)) }
    var symbol: String { movement?.symbol ?? family.symbol }

    static let catalog: [Self] = {
        let goals: [(AchievementFamily, [Int])] = [
            (.repetitions, [1, 3, 5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 500]),
            (.sets, [1, 2, 3, 5, 10, 15, 25, 50]),
            (.days, [1, 2, 3, 5, 7, 10, 14, 21, 28]),
            (.streak, [2, 3, 4, 5, 7, 10, 14, 21, 28]),
            (.sessions, [1, 2, 3, 5, 10, 20])
        ]
        return goals.flatMap { family, targets in
            targets.map { Self(family: family, target: $0) }
        } + FingerExercise.allCases.map { Self(family: .movement, target: 1, movement: $0) }
    }()
}

struct AchievementAward: Identifiable, Equatable {
    let id: String
    let earned: Date
    var acknowledged: Bool
}

struct PracticeDay: Identifiable {
    var id: Date { date }
    let date: Date
    var repetitions = 0
    var seconds = 0.0
}
