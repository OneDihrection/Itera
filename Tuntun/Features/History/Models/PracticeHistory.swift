//
//  PracticeHistory.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

import Foundation

/// One saved day of the daily plan: which items it showed and which of them reached their goal.
struct DailyPlanDay: Equatable, Sendable {
    /// Start of the day.
    let day: Date
    /// Item IDs the plan showed that day (exercise raw values, as `DailyPlanItem.id`).
    let planned: Set<String>
    let completed: Set<String>

    /// Every item the plan showed reached its goal.
    var isComplete: Bool {
        !planned.isEmpty && planned.isSubset(of: completed)
    }
}

/// How much of one day's practice was done.
enum PracticeDayStatus: Equatable {
    case none
    /// Something was practised, but not every plan item reached its goal.
    case partial
    /// Every item of that day's plan reached its goal.
    case completed
}

/// One session's practice of an exercise on a day, as the day's progress page lists it. An
/// exercise practised in several sessions that day has one entry per session.
struct PracticedExercise: Identifiable, Hashable {
    /// Where the exercise's saved report is.
    enum Report: Hashable {
        case finger(UUID)
        case session(UUID)

        var sessionID: UUID {
            switch self {
            case .finger(let id), .session(let id):
                return id
            }
        }
    }

    /// The exercise's raw value, the same ID the daily plan uses.
    let exerciseID: String
    let titleKey: String
    /// The session that practised it; `nil` when only the plan recorded it.
    let report: Report?

    /// Unique within a day: the exercise and its session.
    var id: String {
        guard let report else {
            return exerciseID
        }

        return "\(exerciseID)-\(report.sessionID.uuidString)"
    }
}

/// Practice per calendar day, joined from finger sessions, guided and Balancing sessions and the
/// daily plan's saved days. Built once per refresh; lookups are dictionary reads.
struct PracticeHistory {
    private struct Day {
        var status: PracticeDayStatus = .none
        var exercises: [PracticedExercise] = []
    }

    private let days: [Date: Day]
    private let calendar: Calendar

    static let empty = PracticeHistory(
        fingerSessions: [],
        sessions: [],
        planDays: []
    )

    init(
        fingerSessions: [FingerSessionSummary],
        sessions: [SessionSummary],
        planDays: [DailyPlanDay],
        calendar: Calendar = .current
    ) {
        self.calendar = calendar

        let practice = Self.practiceEvents(
            fingerSessions: fingerSessions,
            sessions: sessions
        )
        let planByDay = Dictionary(
            planDays.map { (calendar.startOfDay(for: $0.day), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let eventsByDay = Dictionary(grouping: practice) { calendar.startOfDay(for: $0.date) }

        var days: [Date: Day] = [:]

        for date in Set(planByDay.keys).union(eventsByDay.keys) {
            days[date] = Self.day(
                events: eventsByDay[date, default: []],
                plan: planByDay[date]
            )
        }

        self.days = days
    }

    // MARK: - Reading

    func status(on date: Date) -> PracticeDayStatus {
        days[calendar.startOfDay(for: date)]?.status ?? .none
    }

    func exercises(on date: Date) -> [PracticedExercise] {
        days[calendar.startOfDay(for: date)]?.exercises ?? []
    }

    /// Every day with some practice, keyed by its start.
    var statuses: [Date: PracticeDayStatus] {
        days.compactMapValues { $0.status == .none ? nil : $0.status }
    }

    /// Days with any practice in the calendar week containing `date`.
    func practiceDayCount(inWeekOf date: Date) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return 0
        }

        // `DateInterval.contains` includes its end, the first day of the next week.
        return days.count { entry in
            entry.key >= week.start
                && entry.key < week.end
                && entry.value.status != .none
        }
    }

    // MARK: - Building

    /// One exercise practised in one session.
    private struct PracticeEvent {
        let date: Date
        let exerciseID: String
        let report: PracticedExercise.Report
    }

    private static func practiceEvents(
        fingerSessions: [FingerSessionSummary],
        sessions: [SessionSummary]
    ) -> [PracticeEvent] {
        let finger = fingerSessions
            .filter { $0.outcome != .savedForLater }
            .flatMap { summary in
                summary.results
                    .filter { $0.repetitions > 0 || $0.activeSeconds > 0 }
                    .map { result in
                        PracticeEvent(
                            date: summary.started,
                            exerciseID: result.kind.rawValue,
                            report: .finger(summary.id)
                        )
                    }
            }

        let guided = sessions.flatMap { summary in
            summary.results
                .filter { $0.outcome == .completed || $0.completedWork > 0 }
                .map { result in
                    PracticeEvent(
                        date: summary.startedAt,
                        exerciseID: result.activity.kind.rawValue,
                        report: .session(summary.id)
                    )
                }
        }

        return (finger + guided).sorted { $0.date < $1.date }
    }

    /// One entry per session of each exercise, in practice order (a session's several sets of
    /// one exercise stay one entry), then plan items recorded without a saved session.
    private static func day(events: [PracticeEvent], plan: DailyPlanDay?) -> Day {
        var exercises: [PracticedExercise] = []
        var seen: Set<PracticedExercise.ID> = []
        var practised: Set<String> = []

        for event in events {
            let exercise = PracticedExercise(
                exerciseID: event.exerciseID,
                titleKey: titleKey(for: event.exerciseID),
                report: event.report
            )

            guard seen.insert(exercise.id).inserted else {
                continue
            }

            practised.insert(event.exerciseID)
            exercises.append(exercise)
        }

        for id in (plan?.completed ?? []).sorted() where practised.insert(id).inserted {
            exercises.append(
                PracticedExercise(
                    exerciseID: id,
                    titleKey: titleKey(for: id),
                    report: nil
                )
            )
        }

        let status: PracticeDayStatus

        if plan?.isComplete == true {
            status = .completed
        } else if exercises.isEmpty {
            status = .none
        } else {
            status = .partial
        }

        return Day(status: status, exercises: exercises)
    }

    /// The plan's title for an exercise ID, matching Beranda's names.
    static func titleKey(for id: String) -> String {
        if let finger = FingerExercise(rawValue: id) {
            return finger.title
        }

        if let balance = BalanceExercise(rawValue: id) {
            return balance.key("title")
        }

        if let kind = TherapyKind(rawValue: id) {
            return "session." + kind.rawValue
        }

        return id
    }
}

// MARK: - Preview data

#if DEBUG
extension PracticeHistory {
    /// Completed and partial days earlier this month, for previews.
    static var preview: PracticeHistory {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let planned: Set<String> = ["opposition", "armRaise", "fullFist", "elbowBend"]

        func day(_ offset: Int, completed: Set<String>) -> DailyPlanDay? {
            calendar.date(byAdding: .day, value: -offset, to: today).map { date in
                DailyPlanDay(day: date, planned: planned, completed: completed)
            }
        }

        let days = [
            day(1, completed: planned),
            day(2, completed: planned),
            day(3, completed: ["opposition", "armRaise"]),
            day(6, completed: planned),
            day(9, completed: ["opposition"]),
        ]

        return PracticeHistory(
            fingerSessions: [],
            sessions: [],
            planDays: days.compactMap { $0 },
            calendar: calendar
        )
    }
}
#endif
