//
//  BalanceSessionLog.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import Foundation

/// Builds the saved history of one Balancing session in the same shape as guided sessions: a
/// one-exercise routine snapshot and one result per set. Saving stays with the view model.
struct BalanceSessionLog {
    let id = UUID()
    let startedAt: Date
    let routine: Routine
    private(set) var results: [SessionActivityResult] = []
    /// Set once the summary has been produced, so a session is finalized at most once.
    private(set) var finalized = false

    var activity: SessionActivity {
        routine.activities[0]
    }

    /// - Parameters:
    ///   - side: The arm that starts; sit-to-stand has no side and ignores it.
    ///   - alternatesSides: Both arms take turns.
    init(
        exercise: BalanceExercise,
        side: TherapySide,
        alternatesSides: Bool,
        goal: Int,
        sets: Int,
        restSeconds: Int,
        date: Date = Date()
    ) {
        let activity = SessionActivity(
            kind: exercise.therapyKind,
            side: side,
            goal: goal,
            sets: sets,
            alternatesSides: alternatesSides && !exercise.isSitToStand
        )

        routine = Routine(activities: [activity], restSeconds: Double(restSeconds))
        startedAt = date
    }

    /// Records one set and returns its execution identity, which its key repetitions share.
    mutating func recordSet(
        number: Int,
        completedWork: Int,
        outcome: ActivityOutcome,
        repMetrics: [RepMetrics]?
    ) -> UUID {
        let executionID = UUID()

        results.append(
            SessionActivityResult(
                executionID: executionID,
                activity: activity,
                outcome: outcome,
                completedWork: max(0, completedWork),
                setNumber: number,
                repMetrics: repMetrics
            )
        )

        return executionID
    }

    var checkpoint: SessionCheckpoint {
        SessionCheckpoint(id: id, routine: routine, startedAt: startedAt, results: results)
    }

    /// The finished summary, or nil when it was already produced or no set was recorded.
    mutating func finalize(stopped: Bool, date: Date = Date()) -> SessionSummary? {
        guard !finalized, !results.isEmpty else {
            return nil
        }

        finalized = true

        return SessionSummary(
            id: id,
            routine: routine,
            startedAt: startedAt,
            endedAt: date,
            stopped: stopped,
            results: results
        )
    }
}
