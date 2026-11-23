//
//  ExerciseProgress.swift
//  Tuntun
//
//  Created by dimaswisodewo on 23/11/2026.
//

import Foundation

/// Which earlier session a day's exercise is compared with on its detail panel.
enum ProgressBaseline: String, CaseIterable, Identifiable, Hashable {
    case firstSession
    case previousSession
    /// The latest session on or before the same weekday a week earlier.
    case weekAgo

    var id: String {
        rawValue
    }

    var titleKey: String {
        "exerciseDetail.baseline." + rawValue
    }
}

/// How an exercise's best repetition is measured.
enum ExerciseMeasure: Equatable {
    /// Degrees, a 2D camera estimate.
    case angle
    /// Share of the calibrated range (finger exercises), 1 being the calibrated target.
    case range
    /// No per-repetition value: fold towel, or sessions saved before repetition metrics.
    case none
}

/// Which way the best repetition moved against a baseline, after camera-noise tolerance.
enum ProgressTrend: Equatable {
    case higher
    case steady
    case lower
}

/// One observation about the day's practice, shown as a row under the progress comparison.
/// Values are in the day's measure (degrees or a share of range) or in seconds for pace.
enum ExerciseInsight: Equatable {
    /// Day's mean seconds per repetition minus the baseline's; negative is quicker.
    case pace(change: Double)
    /// Best minus lowest peak across the day's repetitions.
    case consistency(spread: Double)
    /// The day's last repetition peak minus its first.
    case stamina(change: Double)
    /// Today's repetitions, their difference from the baseline's, and the sessions practised
    /// after the baseline up to the end of the day.
    case volume(repetitions: Int, change: Int, sessionsSince: Int)
}

/// One session on the progress trend: its best repetition in the day's measure.
struct ExerciseTrendPoint: Equatable {
    let date: Date
    let value: Double
    let isBaseline: Bool
    /// The day shown, every session of it joined.
    let isDay: Bool
}

/// One session's practice of one exercise: every set of it in that session.
struct ExerciseSession: Equatable {
    let date: Date
    let report: PracticedExercise.Report
    /// The side practised; nil when both sides took turns or the exercise has no side.
    let side: TherapySide?
    let repetitions: Int
    let activeSeconds: Double
    /// Guided and Balancing sessions keep every credited repetition; finger sessions hold only
    /// the key repetitions, filled in once their replay file is read.
    var metrics: [RepMetrics]

    var peakAngle: Double? {
        metrics.compactMap(\.peakAngle).max()
    }

    var peakFraction: Double? {
        metrics.compactMap(\.peakFraction).max()
    }

    /// Only guided and Balancing sessions keep a duration for every repetition.
    var keepsEveryRepetition: Bool {
        if case .session = report {
            return true
        }

        return false
    }
}

/// One exercise on one day measured against its earlier sessions. Built from values only, so
/// it is cheap to rebuild when a session's metrics arrive.
struct ExerciseProgress {
    /// Changes smaller than these read as steady, given 2D camera noise.
    static let steadyAngleDegrees = 5.0
    static let steadyRangeFraction = 0.05
    static let steadyDurationSeconds = 0.5
    /// Sessions the trend chart shows at most, the day included.
    static let trendLimit = 10

    /// Start of the day shown.
    let day: Date
    /// Sessions practising the exercise on `day`, oldest first.
    let sessionsOnDay: [ExerciseSession]
    /// Sessions before `day`, oldest first.
    private let earlier: [ExerciseSession]
    private let calendar: Calendar

    init(
        sessions: [ExerciseSession],
        day: Date,
        calendar: Calendar = .current
    ) {
        let start = calendar.startOfDay(for: day)
        let sorted = sessions.sorted { $0.date < $1.date }

        self.day = start
        self.calendar = calendar
        sessionsOnDay = sorted.filter { calendar.isDate($0.date, inSameDayAs: start) }
        earlier = sorted.filter { $0.date < start }
    }

    // MARK: - The day

    var measure: ExerciseMeasure {
        if sessionsOnDay.contains(where: { $0.peakAngle != nil }) {
            return .angle
        }

        if sessionsOnDay.contains(where: { $0.peakFraction != nil }) {
            return .range
        }

        return .none
    }

    /// The day's best repetition in `measure`'s unit.
    var peak: Double? {
        peak(of: sessionsOnDay)
    }

    var repetitions: Int {
        sessionsOnDay.reduce(0) { $0 + $1.repetitions }
    }

    var activeSeconds: Double {
        sessionsOnDay.reduce(0) { $0 + $1.activeSeconds }
    }

    /// Mean seconds per repetition: from every repetition's duration when each session kept
    /// them, otherwise from practice time.
    var averageDuration: Double? {
        Self.averageDuration(of: sessionsOnDay)
    }

    /// The side every session of the day practised; nil when they differ or have none.
    var side: TherapySide? {
        let sides = Set(sessionsOnDay.map(\.side))

        guard sides.count == 1 else {
            return nil
        }

        return sides.first ?? nil
    }

    private static func averageDuration(of sessions: [ExerciseSession]) -> Double? {
        let durations = sessions.flatMap(\.metrics).map(\.duration)
        let everyRepetitionKept = sessions.allSatisfy(\.keepsEveryRepetition)

        if everyRepetitionKept, !durations.isEmpty {
            return durations.reduce(0, +) / Double(durations.count)
        }

        let repetitions = sessions.reduce(0) { $0 + $1.repetitions }
        let activeSeconds = sessions.reduce(0) { $0 + $1.activeSeconds }

        guard repetitions > 0, activeSeconds > 0 else {
            return nil
        }

        return activeSeconds / Double(repetitions)
    }

    // MARK: - Baseline

    /// The earlier session `baseline` names; nil when the exercise was not practised then.
    func baselineSession(_ baseline: ProgressBaseline) -> ExerciseSession? {
        switch baseline {
        case .firstSession:
            return earlier.first
        case .previousSession:
            return earlier.last
        case .weekAgo:
            guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: day),
                  let end = calendar.date(byAdding: .day, value: 1, to: weekAgo)
            else {
                return nil
            }

            return earlier.last { $0.date < end }
        }
    }

    /// The baseline session's best repetition in the day's unit.
    func peak(of session: ExerciseSession) -> Double? {
        peak(of: [session])
    }

    /// The day's best repetition minus the baseline's; nil when either has none.
    func change(from session: ExerciseSession) -> Double? {
        guard let current = self.peak,
              let baseline = peak(of: session)
        else {
            return nil
        }

        return current - baseline
    }

    func trend(of change: Double) -> ProgressTrend {
        let tolerance = steadyTolerance

        if change >= tolerance {
            return .higher
        }

        if change <= -tolerance {
            return .lower
        }

        return .steady
    }

    func trend(ofDuration change: Double) -> ProgressTrend {
        if change >= Self.steadyDurationSeconds {
            return .higher
        }

        if change <= -Self.steadyDurationSeconds {
            return .lower
        }

        return .steady
    }

    /// The day's spread of peaks within this reads as even.
    var steadyTolerance: Double {
        measure == .range ? Self.steadyRangeFraction : Self.steadyAngleDegrees
    }

    // MARK: - Trend

    /// Earlier sessions the trend may show, newest last; the caller reads their repetitions so
    /// finger sessions gain a value.
    func recentEarlierSessions(limit: Int) -> [ExerciseSession] {
        Array(earlier.suffix(max(limit - 1, 0)))
    }

    /// Each session's best repetition up to the day, oldest first: at most `limit` points, the
    /// day last, and the baseline kept even when it is older than the rest. Sessions without a
    /// value (finger sessions not yet read, or no measure) are left out.
    func trend(baseline: ExerciseSession?, limit: Int) -> [ExerciseTrendPoint] {
        guard let dayPeak = peak else {
            return []
        }

        var earlierPoints = recentEarlierSessions(limit: limit).compactMap { session in
            point(for: session, baseline: baseline)
        }

        if let baseline,
           !earlierPoints.contains(where: \.isBaseline),
           let baselinePoint = point(for: baseline, baseline: baseline) {
            if earlierPoints.count >= limit - 1 {
                earlierPoints.removeFirst()
            }

            earlierPoints.insert(baselinePoint, at: 0)
        }

        let dayPoint = ExerciseTrendPoint(
            date: day,
            value: dayPeak,
            isBaseline: false,
            isDay: true
        )

        return earlierPoints + [dayPoint]
    }

    private func point(for session: ExerciseSession, baseline: ExerciseSession?) -> ExerciseTrendPoint? {
        guard let value = peak(of: session) else {
            return nil
        }

        return ExerciseTrendPoint(
            date: session.date,
            value: value,
            isBaseline: session == baseline,
            isDay: false
        )
    }

    // MARK: - Insights

    /// Pace, consistency, stamina and volume, in display order; each is left out without
    /// enough data. Finger sessions keep only their key repetitions (first, hardest, last of each
    /// set), so their consistency and stamina rest on those.
    func insights(against baseline: ExerciseSession?) -> [ExerciseInsight] {
        var insights: [ExerciseInsight] = []

        if let baseline,
           let today = averageDuration,
           let before = Self.averageDuration(of: [baseline]) {
            insights.append(.pace(change: today - before))
        }

        let peaks = dayPeaks

        if peaks.count >= 3,
           let best = peaks.max(),
           let lowest = peaks.min() {
            insights.append(.consistency(spread: best - lowest))
        }

        if peaks.count >= 2,
           let first = peaks.first,
           let last = peaks.last {
            insights.append(.stamina(change: last - first))
        }

        if let baseline {
            insights.append(
                .volume(
                    repetitions: repetitions,
                    change: repetitions - baseline.repetitions,
                    sessionsSince: sessionsSince(baseline)
                )
            )
        }

        return insights
    }

    /// Every peak of the day in practice order: sessions oldest first, sets and repetitions as
    /// they were saved.
    private var dayPeaks: [Double] {
        sessionsOnDay.flatMap(\.metrics).compactMap { metrics in
            switch measure {
            case .angle:
                return metrics.peakAngle
            case .range:
                return metrics.peakFraction
            case .none:
                return nil
            }
        }
    }

    /// Sessions after `baseline`, up to and including the day shown.
    private func sessionsSince(_ baseline: ExerciseSession) -> Int {
        earlier.count { $0.date > baseline.date } + sessionsOnDay.count
    }

    private func peak(of sessions: [ExerciseSession]) -> Double? {
        switch measure {
        case .angle:
            return sessions.compactMap(\.peakAngle).max()
        case .range:
            return sessions.compactMap(\.peakFraction).max()
        case .none:
            return nil
        }
    }
}

// MARK: - Peak pose

extension KeyRep {
    /// The frame that differs most from the repetition's first frame: the turn of the movement,
    /// drawn as the repetition's peak pose. Display geometry only, never a scoring rule.
    var peakFrame: SkeletonFrame? {
        guard let start = frames.first else {
            return nil
        }

        return frames.max { first, second in
            first.displacement(from: start) < second.displacement(from: start)
        }
    }
}

private extension SkeletonFrame {
    /// Summed distance of the joints tracked in both frames.
    func displacement(from other: SkeletonFrame) -> Double {
        if let hand, let otherHand = other.hand {
            return zip(hand, otherHand).reduce(0) { total, pair in
                guard let point = pair.0, let otherPoint = pair.1 else {
                    return total
                }

                return total + Self.distance(point, otherPoint)
            }
        }

        return joints.reduce(0) { total, entry in
            guard let otherPoint = other.joints[entry.key] else {
                return total
            }

            return total + Self.distance(entry.value, otherPoint)
        }
    }

    static func distance(_ a: TherapyPoint, _ b: TherapyPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
