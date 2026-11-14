//
//  FingerSessionRecord.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

struct FingerSessionRecord: Codable {
    let version: Int
    let category: String?
    let id: UUID
    let started: Date
    let ended: Date
    let side: String
    let sets: Int
    let repetitions: Int
    let rest: Int
    let voice: Bool
    let ambient: Bool
    let outcome: String
    let feeling: String?
    let exerciseIndex: Int
    let results: [ResultRecord]
    /// The single exercise a daily-plan session ran; absent for whole-program sessions and in
    /// records written before it existed.
    let only: String?

    struct ResultRecord: Codable {
        let kind: String
        let sets: Int
        let repetitions: Int
        let seconds: Double
        let gain: Double?
        let completed: Bool
        let skipped: Bool?
        /// Absent in records written before angles were recorded.
        let angles: [AngleRecord]?
    }

    /// Two held-angle ranges per metric, in degrees: summary values only, never a stream.
    struct AngleRecord: Codable {
        let metric: String
        let beforeMinimum: Double?
        let beforeMaximum: Double?
        let afterMinimum: Double?
        let afterMaximum: Double?
        let threeD: Bool

        init(_ result: FingerAngleResult) {
            metric = result.metric.rawValue
            beforeMinimum = result.before?.minimum
            beforeMaximum = result.before?.maximum
            afterMinimum = result.after?.minimum
            afterMaximum = result.after?.maximum
            threeD = result.threeD
        }

        func domain() throws -> FingerAngleResult {
            guard let metric = FingerAngleMetric(rawValue: metric) else {
                throw RecordError.invalid
            }

            return FingerAngleResult(
                metric: metric,
                before: try Self.range(beforeMinimum, beforeMaximum),
                after: try Self.range(afterMinimum, afterMaximum),
                threeD: threeD
            )
        }

        /// Both bounds or neither, finite, ordered and within a joint's possible range.
        private static func range(_ minimum: Double?, _ maximum: Double?) throws -> AngleRange? {
            switch (minimum, maximum) {
            case (nil, nil):
                return nil
            case let (minimum?, maximum?):
                guard minimum.isFinite, maximum.isFinite, minimum <= maximum,
                      minimum >= -180, maximum <= 180 else {
                    throw RecordError.invalid
                }

                return AngleRange(minimum: minimum, maximum: maximum)
            default:
                throw RecordError.invalid
            }
        }
    }

    init(_ summary: FingerSessionSummary) {
        version = 1
        category = summary.routine.category.rawValue
        id = summary.id
        started = summary.started
        ended = summary.ended
        side = summary.routine.side.rawValue
        sets = summary.routine.sets
        repetitions = summary.routine.repetitions
        rest = summary.routine.restSeconds
        voice = summary.routine.voiceControl
        ambient = summary.routine.ambientSound
        outcome = summary.outcome.rawValue
        feeling = summary.feeling?.rawValue
        exerciseIndex = summary.exerciseIndex
        only = summary.routine.only?.rawValue
        results = summary.results.map {
            ResultRecord(kind: $0.kind.rawValue, sets: $0.completedSets,
                         repetitions: $0.repetitions, seconds: $0.activeSeconds,
                         gain: $0.observedGain, completed: $0.completed, skipped: $0.skipped,
                         angles: $0.angles.isEmpty ? nil : $0.angles.map(AngleRecord.init))
        }
    }

    func domain() throws -> FingerSessionSummary {
        guard version == 1, let side = TrainingSide(rawValue: side),
              let outcome = SessionOutcome(rawValue: outcome),
              (1...5).contains(sets), (1...20).contains(repetitions),
              (5...120).contains(rest), (0..<5).contains(exerciseIndex),
              feeling == nil || SessionFeeling(rawValue: feeling!) != nil else { throw RecordError.invalid }
        var routine = FingerRoutine()
        // Records written before categories existed are finger sessions.
        routine.category = category.flatMap(ExerciseCategory.init(rawValue:)) ?? .fingers
        routine.side = side
        routine.sets = sets
        routine.repetitions = repetitions
        routine.restSeconds = rest
        routine.voiceControl = voice
        routine.ambientSound = ambient
        routine.only = only.flatMap(FingerExercise.init(rawValue:))
        let mapped = try results.map { result -> FingerExerciseResult in
            guard let kind = FingerExercise(rawValue: result.kind),
                  result.sets >= 0, result.sets <= sets, result.repetitions >= 0,
                  result.repetitions <= sets * repetitions,
                  !result.completed || (result.sets == sets && result.repetitions == sets * repetitions),
                  result.seconds.isFinite, result.seconds >= 0,
                  result.gain == nil || (result.gain!.isFinite && result.gain! >= 0) else { throw RecordError.invalid }
            return FingerExerciseResult(kind: kind, completedSets: result.sets,
                                        repetitions: result.repetitions, activeSeconds: result.seconds,
                                        observedGain: result.gain, completed: result.completed, skipped: result.skipped ?? false,
                                        // Angles are supplementary: an unreadable one is dropped, never the session.
                                        angles: (result.angles ?? []).compactMap { try? $0.domain() })
        }
        guard Set(mapped.map(\.kind)).count == mapped.count else {
            throw RecordError.invalid
        }
        return FingerSessionSummary(id: id, started: started, ended: ended, routine: routine,
                                    results: mapped, outcome: outcome,
                                    feeling: feeling.flatMap(SessionFeeling.init(rawValue:)), exerciseIndex: exerciseIndex)
    }

    enum RecordError: Error { case invalid }
}
