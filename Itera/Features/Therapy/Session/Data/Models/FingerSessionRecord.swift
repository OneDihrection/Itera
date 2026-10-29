//
//  FingerSessionRecord.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

struct FingerSessionRecord: Codable {
    let version: Int
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

    struct ResultRecord: Codable {
        let kind: String
        let sets: Int
        let repetitions: Int
        let seconds: Double
        let gain: Double?
        let completed: Bool
        let skipped: Bool?
    }

    init(_ summary: FingerSessionSummary) {
        version = 1
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
        results = summary.results.map {
            ResultRecord(kind: $0.kind.rawValue, sets: $0.completedSets,
                         repetitions: $0.repetitions, seconds: $0.activeSeconds,
                         gain: $0.observedGain, completed: $0.completed, skipped: $0.skipped)
        }
    }

    func domain() throws -> FingerSessionSummary {
        guard version == 1, let side = TrainingSide(rawValue: side),
              let outcome = SessionOutcome(rawValue: outcome),
              (1...5).contains(sets), (1...20).contains(repetitions),
              (5...120).contains(rest), (0..<5).contains(exerciseIndex),
              feeling == nil || SessionFeeling(rawValue: feeling!) != nil else { throw RecordError.invalid }
        var routine = FingerRoutine()
        routine.side = side
        routine.sets = sets
        routine.repetitions = repetitions
        routine.restSeconds = rest
        routine.voiceControl = voice
        routine.ambientSound = ambient
        let mapped = try results.map { result -> FingerExerciseResult in
            guard let kind = FingerExercise(rawValue: result.kind),
                  result.sets >= 0, result.sets <= sets, result.repetitions >= 0,
                  result.repetitions <= sets * repetitions,
                  !result.completed || (result.sets == sets && result.repetitions == sets * repetitions),
                  result.seconds.isFinite, result.seconds >= 0,
                  result.gain == nil || (result.gain!.isFinite && result.gain! >= 0) else { throw RecordError.invalid }
            return FingerExerciseResult(kind: kind, completedSets: result.sets,
                                        repetitions: result.repetitions, activeSeconds: result.seconds,
                                        observedGain: result.gain, completed: result.completed, skipped: result.skipped ?? false)
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
