//
//  SessionProgress.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

/// Session ordering and outcome bookkeeping, independent of camera and UI services.
struct SessionProgress {
    enum Stage: Equatable {
        case activity
        case feedback(UUID)
        case rest(deadline: Double)
        case summary
    }

    let id = UUID()
    let routine: Routine
    let startedAt: Date
    private(set) var index = 0
    private(set) var setNumber = 1
    private(set) var executionID = UUID()
    private(set) var stage: Stage = .activity
    private(set) var results: [SessionActivityResult] = []
    private(set) var pausedAt: Double?
    private(set) var summary: SessionSummary?

    var currentActivity: SessionActivity? {
        guard routine.activities.indices.contains(index), stage != .summary else {
            return nil
        }

        return routine.activities[index]
    }

    init(routine: Routine, startedAt: Date) {
        self.routine = routine
        self.startedAt = startedAt
    }

    mutating func pause(at time: Double) {
        guard time.isFinite, pausedAt == nil, stage != .summary else {
            return
        }

        pausedAt = time
    }

    mutating func resume(at time: Double) {
        guard time.isFinite, let suspendedAt = pausedAt, time >= suspendedAt else {
            return
        }

        if case .rest(let deadline) = stage {
            stage = .rest(deadline: deadline + time - suspendedAt)
        }

        pausedAt = nil
    }

    mutating func retryExecution() {
        guard stage == .activity else { return }
        executionID = UUID()
    }

    mutating func record(
        execution: UUID,
        outcome: ActivityOutcome,
        completedWork: Int,
        reachOutcomes: [ReachOutcome] = [],
        skippedReachSteps: [ReachSkippedStep]? = nil,
        practiceSeconds: Double = 0
    ) {
        guard pausedAt == nil,
            stage == .activity,
            execution == executionID,
            let activity = currentActivity,
            !results.contains(where: { $0.executionID == execution })
        else {
            return
        }

        results.append(
            SessionActivityResult(
                executionID: execution,
                activity: activity,
                outcome: outcome,
                completedWork: max(0, completedWork),
                reachOutcomes: reachOutcomes,
                skippedReachSteps: skippedReachSteps,
                practiceSeconds: practiceSeconds,
                setNumber: setNumber
            )
        )
        stage = .feedback(UUID())
    }

    mutating func finishFeedback(request: UUID, at time: Double, date: Date) {
        guard time.isFinite, pausedAt == nil, stage == .feedback(request) else {
            return
        }

        if !hasNextSet, index + 1 == routine.activities.count {
            finalize(stopped: false, date: date)
            return
        }

        stage = .rest(deadline: time + max(0, routine.restSeconds))
    }

    mutating func tick(at time: Double) {
        guard time.isFinite,
            pausedAt == nil,
            case .rest(let deadline) = stage,
            time >= deadline
        else {
            return
        }

        if hasNextSet {
            setNumber += 1
        } else {
            index += 1
            setNumber = 1
        }
        executionID = UUID()
        stage = .activity
    }

    var hasNextSet: Bool {
        guard let activity = currentActivity, let last = results.last else {
            return false
        }
        return last.activity.id == activity.id
            && last.outcome == .completed
            && setNumber < activity.sets
    }

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
        stage = .summary
        pausedAt = nil
    }
}
