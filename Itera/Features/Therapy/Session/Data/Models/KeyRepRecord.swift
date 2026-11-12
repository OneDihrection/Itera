//
//  KeyRepRecord.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import Foundation

/// The saved, self-describing form of one session's key-repetition skeletons.
///
/// The file names its joint order, coordinate space and scale so it can later be exported and
/// read without the app's types. Each frame stores x, y pairs in `jointOrder`, quantized to
/// `scale`; `missingValue` marks a joint that was not confidently tracked in that frame.
struct KeyRepRecord: Codable {
    static let currentVersion = 1
    static let coordinateSpace = "vision-normalized-unmirrored-origin-bottom-left"
    static let scale = 10_000
    static let missingValue: Int16 = -1

    struct ActivityRecord: Codable {
        let executionID: UUID
        let activity: SessionActivity
        let setNumber: Int
        let reps: [RepRecord]
    }

    struct RepRecord: Codable {
        let roles: [KeyRepRole]
        let metrics: RepMetrics
        let aspectRatio: Double
        /// Milliseconds since the repetition's first recorded frame.
        let frameTimes: [Int]
        let frames: [[Int16]]
    }

    let version: Int
    let sessionID: UUID
    let coordinateSpace: String
    let scale: Int
    let jointOrder: [BodyJoint]
    var activities: [ActivityRecord]

    init(sessionID: UUID, activities: [ActivityKeyReps] = []) {
        version = Self.currentVersion
        self.sessionID = sessionID
        coordinateSpace = Self.coordinateSpace
        scale = Self.scale
        jointOrder = BodyJoint.allCases
        self.activities = activities.map { Self.record($0, jointOrder: BodyJoint.allCases) }
    }

    /// Replaces any earlier recording of the same set, so a repeated save stays idempotent.
    mutating func upsert(_ value: ActivityKeyReps) {
        activities.removeAll { $0.executionID == value.executionID }
        activities.append(Self.record(value, jointOrder: jointOrder))
    }

    // MARK: - Domain mapping

    func domain() -> [ActivityKeyReps] {
        activities.map { activity in
            ActivityKeyReps(
                executionID: activity.executionID,
                activity: activity.activity,
                setNumber: activity.setNumber,
                reps: activity.reps.map(domainRep)
            )
        }
    }

    private func domainRep(_ rep: RepRecord) -> KeyRep {
        let frames = zip(rep.frameTimes, rep.frames).compactMap { time, values -> SkeletonFrame? in
            // A frame of the wrong width cannot be mapped onto the joint order, so it is skipped.
            guard values.count == jointOrder.count * 2 else {
                return nil
            }

            var joints: [BodyJoint: TherapyPoint] = [:]

            for (index, joint) in jointOrder.enumerated() {
                let x = values[index * 2]
                let y = values[index * 2 + 1]

                guard x != Self.missingValue, y != Self.missingValue else {
                    continue
                }

                joints[joint] = TherapyPoint(
                    x: Double(x) / Double(scale),
                    y: Double(y) / Double(scale)
                )
            }

            return SkeletonFrame(time: Double(time) / 1000, joints: joints)
        }

        return KeyRep(
            roles: rep.roles,
            metrics: rep.metrics,
            aspectRatio: rep.aspectRatio,
            frames: frames
        )
    }

    private static func record(_ value: ActivityKeyReps, jointOrder: [BodyJoint]) -> ActivityRecord {
        ActivityRecord(
            executionID: value.executionID,
            activity: value.activity,
            setNumber: value.setNumber,
            reps: value.reps.map { rep in
                RepRecord(
                    roles: rep.roles,
                    metrics: rep.metrics,
                    aspectRatio: rep.aspectRatio,
                    frameTimes: rep.frames.map { Int(($0.time * 1000).rounded()) },
                    frames: rep.frames.map { quantized($0, jointOrder: jointOrder) }
                )
            }
        )
    }

    private static func quantized(_ frame: SkeletonFrame, jointOrder: [BodyJoint]) -> [Int16] {
        var values: [Int16] = []
        values.reserveCapacity(jointOrder.count * 2)

        for joint in jointOrder {
            guard let point = frame.joints[joint] else {
                values.append(missingValue)
                values.append(missingValue)
                continue
            }

            values.append(quantized(point.x))
            values.append(quantized(point.y))
        }

        return values
    }

    private static func quantized(_ value: Double) -> Int16 {
        Int16((min(1, max(0, value)) * Double(scale)).rounded())
    }
}
