//
//  Session.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum SessionCommand {
    case pause
    case resume
    case stop
    case repeatInstruction
    case help
    case redo
    case adjustTarget
    case retryStep
    case skipStep
    case retryCalibration
    case skip
    case timedPractice
    #if DEBUG
    /// Developer shortcut: records the current activity's remaining sets as completed at their goal.
    case debugFinish
    #endif
}

enum ActivityOutcome: String, Codable {
    case completed
    case skipped
    case interrupted
}

struct SessionActivityResult: Codable, Equatable {
    let executionID: UUID
    let activity: SessionActivity
    let outcome: ActivityOutcome
    let completedWork: Int
    var reachOutcomes: [ReachOutcome] = []
    var skippedReachSteps: [ReachSkippedStep]? = nil
    var practiceSeconds: Double = 0
    /// Absent in summaries saved before per-exercise sets were introduced.
    var setNumber: Int? = nil
    /// One entry per credited repetition; absent in summaries saved before repetition metrics.
    var repMetrics: [RepMetrics]? = nil
}

struct SessionSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let routine: Routine
    let startedAt: Date
    let endedAt: Date
    let stopped: Bool
    var interrupted = false
    let results: [SessionActivityResult]

    var completedSets: Int {
        results.filter { $0.activity.kind != .sitToStand && $0.outcome == .completed }.count
    }
}
