//
//  SharedResultBuilder.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

/// Turns saved session history into the summary values the doctor receives.
enum SharedResultBuilder {
    static func results(
        from summary: FingerSessionSummary,
        version: Int?
    ) -> [SharedExerciseResult] {
        summary.results.compactMap { result in
            guard !result.skipped || result.repetitions > 0 else {
                return nil
            }

            let exercise = result.kind.rawValue

            return SharedExerciseResult(
                id: "\(summary.id.uuidString)-\(exercise)-\(summary.routine.side.rawValue)",
                sessionID: summary.id,
                date: summary.started,
                exercise: exercise,
                side: summary.routine.side,
                completedSets: result.completedSets,
                plannedSets: summary.routine.sets,
                work: result.repetitions,
                completed: result.completed,
                practiceSeconds: result.activeSeconds,
                angles: result.angles.map { angle in
                    SharedAngle(
                        titleKey: angle.metric.titleKey,
                        before: angle.before,
                        after: angle.after,
                        threeD: angle.threeD
                    )
                },
                prescriptionVersion: version
            )
        }
    }

    /// Therapy sessions save one result per set; the doctor sees one row per activity and side.
    static func results(
        from summary: SessionSummary,
        version: Int?
    ) -> [SharedExerciseResult] {
        summary.routine.activities.compactMap { activity in
            let sets = summary.results.filter { $0.activity.id == activity.id }

            guard !sets.isEmpty else {
                return nil
            }

            let completedSets = sets.filter { $0.outcome == .completed }.count
            let side = activity.side == .left ? HandSide.left : .right
            let angles = sets.last { $0.angles?.isEmpty == false }?.angles ?? []

            return SharedExerciseResult(
                id: "\(summary.id.uuidString)-\(activity.kind.rawValue)-\(side.rawValue)",
                sessionID: summary.id,
                date: summary.startedAt,
                exercise: activity.kind.rawValue,
                side: side,
                completedSets: completedSets,
                plannedSets: activity.sets,
                work: sets.reduce(0) { $0 + $1.completedWork },
                completed: completedSets >= activity.sets,
                practiceSeconds: sets.reduce(0) { $0 + $1.practiceSeconds },
                angles: angles.compactMap { angle in
                    angle.bodyAngle.map { body in
                        SharedAngle(
                            titleKey: body.titleKey,
                            before: angle.before,
                            after: angle.after,
                            threeD: angle.threeD
                        )
                    }
                },
                prescriptionVersion: version
            )
        }
    }
}
