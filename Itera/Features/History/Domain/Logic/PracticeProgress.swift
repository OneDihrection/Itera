//
//  PracticeProgress.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

/// Calendar-week reporting uses saved sessions, including partial attempts.
struct PracticeReport {
    let sessions: [FingerSessionSummary]
    let currentWeek: [FingerSessionSummary]
    let days: [Date]
    let sessionsByDay: [Date: [FingerSessionSummary]]
    let weeklyRepetitions: [Int]

    init(history: [FingerSessionSummary], now: Date = Date(), calendar: Calendar = .current) {
        sessions = history.filter { $0.outcome != .savedForLater && $0.ended <= now }
            .sorted { $0.ended > $1.ended }
        sessionsByDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.ended) }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        currentWeek = sessions.filter { $0.ended >= weekStart }
        let weeks = Dictionary(grouping: sessions) {
            calendar.dateInterval(of: .weekOfYear, for: $0.ended)?.start
        }
        weeklyRepetitions = (-3...0).map { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: weekStart) else {
                return 0
            }
            return weeks[start, default: []].reduce(0) { $0 + $1.totalRepetitions }
        }
    }

    static func minutes(_ seconds: Double) -> Int {
        seconds > 0 ? max(1, Int((seconds / 60).rounded())) : 0
    }
}
