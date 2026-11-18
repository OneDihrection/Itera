//
//  SessionProgress.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

/// Session ordering and outcome bookkeeping, independent of camera and UI services. Which stage
/// the session is in belongs to `SessionEngine`; this type only knows the current activity, set
/// and execution, the recorded results and the final summary.
struct SessionProgress {
    /// What follows a finished rest.
    enum NextUnit {
        case set
        case activity
    }

    let id = UUID()
    let routine: Routine
    let startedAt: Date
    private(set) var index = 0
    private(set) var setNumber = 1
    private(set) var executionID = UUID()
    private(set) var results: [SessionActivityResult] = []
    private(set) var summary: SessionSummary?

    var currentActivity: SessionActivity? {
        guard routine.activities.indices.contains(index), summary == nil else {
            return nil
        }

        return routine.activities[index]
    }

    init(routine: Routine, startedAt: Date) {
        self.routine = routine
        self.startedAt = startedAt
    }

    mutating func retryExecution() {
        executionID = UUID()
    }

    /// Records the current execution's outcome once. Returns false when there is no current
    /// activity or the execution already has a result.
    mutating func record(
        outcome: ActivityOutcome,
        completedWork: Int,
        reachOutcomes: [ReachOutcome] = [],
        skippedReachSteps: [ReachSkippedStep]? = nil,
        practiceSeconds: Double = 0,
        repMetrics: [RepMetrics]? = nil
    ) -> Bool {
        guard let activity = currentActivity,
            !results.contains(where: { $0.executionID == executionID })
        else {
            return false
        }

        results.append(
            SessionActivityResult(
                executionID: executionID,
                activity: activity,
                outcome: outcome,
                completedWork: max(0, completedWork),
                reachOutcomes: reachOutcomes,
                skippedReachSteps: skippedReachSteps,
                practiceSeconds: practiceSeconds,
                setNumber: setNumber,
                repMetrics: repMetrics
            )
        )
        return true
    }

    /// Ends the session after the routine's last set. Returns true when it did.
    mutating func finishIfLastSet(date: Date) -> Bool {
        guard !hasNextSet, index + 1 == routine.activities.count else {
            return false
        }

        finalize(stopped: false, date: date)
        return true
    }

    /// Moves to the next set of this activity, or to the next activity, with a new execution.
    mutating func advanceAfterRest() -> NextUnit {
        let next: NextUnit

        if hasNextSet {
            setNumber += 1
            next = .set
        } else {
            index += 1
            setNumber = 1
            next = .activity
        }

        executionID = UUID()
        return next
    }

    var hasNextSet: Bool {
        guard let activity = currentActivity, let last = results.last else {
            return false
        }
        return last.activity.id == activity.id
            && last.outcome == .completed
            && setNumber < activity.sets
    }

    #if DEBUG
    /// Developer shortcut: records every remaining set of the current activity as completed at its
    /// goal, then ends the session after the last activity. Otherwise the engine rests until the
    /// next one. The credited work is invented, so this exists only in debug builds.
    mutating func completeCurrentActivityForDebug(date: Date) {
        guard let activity = currentActivity else {
            return
        }

        // In feedback or rest the current set is already recorded; continue from the next one.
        let currentSetRecorded = results.contains { $0.executionID == executionID }
        let firstSet = currentSetRecorded ? setNumber + 1 : setNumber

        if firstSet <= activity.sets {
            for number in firstSet...activity.sets {
                results.append(
                    SessionActivityResult(
                        executionID: number == setNumber ? executionID : UUID(),
                        activity: activity,
                        outcome: .completed,
                        completedWork: activity.goal,
                        setNumber: number
                    )
                )
            }
        }

        setNumber = activity.sets

        guard index + 1 < routine.activities.count else {
            finalize(stopped: false, date: date)
            return
        }
    }
    #endif

    mutating func finalize(stopped: Bool, date: Date) {
        guard summary == nil else {
            return
        }

        summary = SessionSummary(
            id: id,
            routine: routine,
            startedAt: startedAt,
            endedAt: date,
            stopped: stopped,
            results: results
        )
    }
}
