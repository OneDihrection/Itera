//
//  KeyRepRecording.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import Foundation

/// Measurements for one accepted repetition, kept for every repetition of a set.
///
/// Angles are 2D camera estimates in degrees, not clinical goniometry. They describe the
/// activity's own movement: the shoulder angle for arm raise and elbow flexion for elbow bend.
/// Directional reach has no single joint angle, so its angles are nil.
struct RepMetrics: Codable, Equatable {
    let repNumber: Int
    /// Seconds from the end of the previous repetition (or practice start) to this one's credit.
    let duration: Double
    let startAngle: Double?
    let peakAngle: Double?
    /// Share of recorded frames in which every joint the angle needs was confidently tracked.
    let trackingCoverage: Double
    /// The arm that moved, when the exercise lets both arms take turns.
    var side: TherapySide? = nil

    var observedRange: Double? {
        guard let startAngle, let peakAngle else {
            return nil
        }

        return peakAngle - startAngle
    }
}

enum KeyRepRole: String, Codable, CaseIterable {
    case first
    case hardest
    case last
}

/// One recorded pose: confidently tracked joints only, in Vision's normalized, unmirrored image
/// space (origin bottom-left). A missing joint was not usable in that frame.
struct SkeletonFrame: Equatable {
    /// Seconds since the first recorded frame of the repetition.
    let time: Double
    let joints: [BodyJoint: TherapyPoint]
}

/// The skeleton of one repetition kept for replay. One repetition can hold several roles, for
/// example when the first repetition is also the hardest.
struct KeyRep: Equatable {
    var roles: [KeyRepRole]
    let metrics: RepMetrics
    /// Image width divided by height, needed to draw normalized joints without distortion.
    let aspectRatio: Double
    let frames: [SkeletonFrame]
}

/// The key repetitions recorded for one set of one activity.
struct ActivityKeyReps: Equatable {
    let executionID: UUID
    let activity: SessionActivity
    let setNumber: Int
    let reps: [KeyRep]
}
