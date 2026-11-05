//
//  PracticeProgress.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

/// Rewards participation recorded by the session engine, never inferred recovery or extra exercise.
struct PracticeProgress {
    private(set) var repetitions = 0
    private(set) var sets = 0
    private(set) var sessions = 0
    private(set) var currentStreak = 0
    private(set) var bestStreak = 0
    private(set) var days: [Date: PracticeDay] = [:]
    private(set) var candidates: [AchievementAward] = []
    private(set) var movements = Set<FingerExercise>()
    let today: Date
    let calendar: Calendar

    init(history: [FingerSessionSummary] = [], now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        var seenSessions = Set<UUID>()
        var earned = Set<String>()
        var lastDay: Date?
        var run = 0

        for session in history.sorted(by: { $0.ended < $1.ended }) {
            let day = calendar.startOfDay(for: session.ended)
            guard session.outcome != .savedForLater, session.totalRepetitions > 0,
                  day <= today, seenSessions.insert(session.id).inserted else {
                continue
            }
            repetitions += session.totalRepetitions
            sets += session.totalSets
            sessions += 1
            var daily = days[day] ?? PracticeDay(date: day)
            daily.repetitions += session.totalRepetitions
            daily.seconds += session.duration
            days[day] = daily
            for result in session.results where result.repetitions > 0 {
                movements.insert(result.kind)
            }
            if day != lastDay {
                let consecutive = lastDay.map { calendar.dateComponents([.day], from: $0, to: day).day == 1 } ?? false
                run = consecutive ? run + 1 : 1
                bestStreak = max(bestStreak, run)
                lastDay = day
            }
            for badge in PracticeAchievement.catalog where !earned.contains(badge.id) {
                if value(for: badge) >= badge.target {
                    candidates.append(AchievementAward(id: badge.id, earned: session.ended, acknowledged: false))
                    earned.insert(badge.id)
                }
            }
        }
        if let lastDay, calendar.dateComponents([.day], from: lastDay, to: today).day ?? 2 <= 1 {
            currentStreak = run
        }
    }

    func value(for badge: PracticeAchievement) -> Int {
        switch badge.family {
        case .repetitions: return repetitions
        case .sets: return sets
        case .days: return days.count
        case .streak: return bestStreak
        case .sessions: return sessions
        case .movement: return badge.movement.map { movements.contains($0) ? 1 : 0 } ?? 0
        }
    }

    func week(offset: Int) -> [PracticeDay] {
        (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: offset * 7 - 6 + index, to: today) else {
                return nil
            }
            return days[date] ?? PracticeDay(date: date)
        }
    }
}
