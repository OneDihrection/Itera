//
//  FingerSessionEngine.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

struct FingerSessionEngine {
    private(set) var summary: FingerSessionSummary
    private(set) var activity: FingerActivity
    private(set) var paused = false
    private(set) var finished = false

    init(routine: FingerRoutine, checkpoint: FingerSessionSummary? = nil) {
        summary = checkpoint ?? FingerSessionSummary(
            id: UUID(), started: Date(), ended: Date(), routine: routine,
            results: [], outcome: .interrupted, exerciseIndex: 0
        )
        var index = min(summary.exerciseIndex, routine.exercises.count - 1)
        if summary.results.contains(where: { $0.kind == routine.exercises[index] && ($0.completed || $0.skipped) }) {
            if index + 1 < routine.exercises.count {
                index += 1
                summary.exerciseIndex = index
            } else {
                finished = true
            }
        }
        let prior = summary.results.first { $0.kind == routine.exercises[index] && !$0.completed && !$0.skipped }
        activity = FingerActivity(kind: routine.exercises[index], routine: routine, restAfterFinalSet: index < routine.exercises.count - 1)
        if let prior {
            activity.restore(prior)
        }
    }





    mutating func pause() {
        paused = true
        activity.suspendClock()
        activity.breakEvidence()
    }

    mutating func resume() {
        paused = false
        activity.suspendClock()
        activity.breakEvidence()
    }

    mutating func recalibrate() { activity.recalibrate() }
    mutating func guidanceStarted() { activity.guidanceStarted() }
    mutating func guidanceCompleted() { activity.guidanceCompleted() }

    mutating func observe(_ evidence: HandEvidence, now: Double) {
        guard !paused, !finished else {
            return
        }
        activity.observe(evidence, now: now)
    }

    mutating func suspendEvidence() { activity.suspendEvidence() }

    mutating func loseEvidence() { activity.breakEvidence() }

    mutating func tick(_ now: Double, ready: Bool) {
        guard !paused, !finished else {
            return
        }
        activity.tick(now, ready: ready)
        guard activity.phase == .finished else {
            return
        }
        captureCurrent()
        if summary.exerciseIndex + 1 < summary.routine.exercises.count {
            summary.exerciseIndex += 1
            activity = FingerActivity(kind: summary.routine.exercises[summary.exerciseIndex], routine: summary.routine,
                                      restAfterFinalSet: summary.exerciseIndex < summary.routine.exercises.count - 1)
        } else {
            finished = true
        }
    }

    mutating func skipCurrent() {
        guard paused, !finished else {
            return
        }
        captureCurrent()
        if let index = summary.results.firstIndex(where: { $0.kind == activity.kind }),
           !summary.results[index].completed {
            summary.results[index].skipped = true
        }
        if summary.exerciseIndex + 1 < summary.routine.exercises.count {
            summary.exerciseIndex += 1
            activity = FingerActivity(kind: summary.routine.exercises[summary.exerciseIndex], routine: summary.routine,
                                      restAfterFinalSet: summary.exerciseIndex < summary.routine.exercises.count - 1)
        } else {
            finished = true
        }
    }

    mutating func snapshot(outcome: SessionOutcome) -> FingerSessionSummary {
        captureCurrent()
        summary.ended = Date()
        summary.outcome = outcome
        return summary
    }

    private mutating func captureCurrent() {
        if summary.results.contains(where: { $0.kind == activity.kind && $0.skipped }) {
            return
        }
        let result = FingerExerciseResult(
            kind: activity.kind, completedSets: activity.completedSets,
            repetitions: activity.totalRepetitions, activeSeconds: activity.activeSeconds,
            observedGain: activity.observedGain,
            completed: activity.completedSets >= summary.routine.sets
        )
        summary.results.removeAll { $0.kind == activity.kind }
        summary.results.append(result)
    }
}
