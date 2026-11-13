//
//  FingerKeyRepRecord.swift
//  Itera
//
//  Created by dimaswisodewo on 13/11/2026.
//

import Foundation

/// The saved form of one finger session's key-repetition hand skeletons.
///
/// It shares `KeyRepRecord`'s self-describing layout: coordinate space, scale and the hand joint
/// order are named in the file, and each repetition is a `KeyRepRecord.RepRecord` whose body
/// frames are empty and whose `hand` holds 21 quantized x, y pairs per frame.
struct FingerKeyRepRecord: Codable {
    static let currentVersion = 1

    struct SetRecord: Codable {
        /// `FingerExercise` raw value, never a display string.
        let exercise: String
        let setNumber: Int
        let reps: [KeyRepRecord.RepRecord]
    }

    let version: Int
    let sessionID: UUID
    let coordinateSpace: String
    let scale: Int
    let handJointOrder: [String]
    var sets: [SetRecord]

    init(sessionID: UUID) {
        version = Self.currentVersion
        self.sessionID = sessionID
        coordinateSpace = KeyRepRecord.coordinateSpace
        scale = KeyRepRecord.scale
        handJointOrder = KeyRepRecord.handJointOrder
        sets = []
    }

    /// Replaces any earlier recording of the same exercise and set, so a repeated save stays
    /// idempotent.
    mutating func upsert(_ value: FingerKeyReps) {
        sets.removeAll { $0.exercise == value.exercise.rawValue && $0.setNumber == value.setNumber }
        sets.append(
            SetRecord(
                exercise: value.exercise.rawValue,
                setNumber: value.setNumber,
                reps: value.reps.map { KeyRepRecord.repRecord($0, jointOrder: []) }
            )
        )
    }

    /// Sets whose exercise this app version no longer knows are skipped.
    func domain() -> [FingerKeyReps] {
        sets.compactMap { set in
            guard let exercise = FingerExercise(rawValue: set.exercise) else {
                return nil
            }

            return FingerKeyReps(
                exercise: exercise,
                setNumber: set.setNumber,
                reps: set.reps.map { KeyRepRecord.domainRep($0, jointOrder: [], scale: scale) }
            )
        }
    }
}
