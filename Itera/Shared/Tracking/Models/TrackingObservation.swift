//
//  TrackingObservation.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum BodyJoint: String, CaseIterable {
    case nose, neck, root, leftShoulder, rightShoulder, leftElbow, rightElbow
    case leftWrist, rightWrist, leftHip, rightHip
    case leftKnee, rightKnee, leftAnkle, rightAnkle
}

struct TherapyPoint: Equatable {
    var x: Double
    var y: Double

    static func + (a: Self, b: Self) -> Self { Self(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { Self(x: a.x - b.x, y: a.y - b.y) }
    func scaled(_ scale: Double) -> Self { Self(x: x * scale, y: y * scale) }
    var length: Double { hypot(x, y) }
}

struct TrackingObservation {
    struct Landmark {
        let position: TherapyPoint
        let confidence: Float
    }

    let timestamp: Double
    let generation: UUID
    let width: Int
    let height: Int
    /// People whose landmarks are reported: 1 once the patient has been selected from
    /// everyone in view, otherwise the number of people detected (0, or several when ambiguous).
    let personCount: Int
    let joints: [BodyJoint: Landmark]
    var hand: HandEvidence? = nil
    var workspaceMirrored = false
    /// Changes whenever a different person is locked as the patient, so smoothing can restart.
    var subjectEpoch = 0

    var aspect: Double { Double(width) / Double(max(1, height)) }

    func point(_ joint: BodyJoint, minimumConfidence: Float = 0.5) -> TherapyPoint? {
        guard personCount == 1,
            let landmark = joints[joint],
            landmark.confidence.isFinite,
            landmark.confidence >= minimumConfidence,
            landmark.position.x.isFinite,
            landmark.position.y.isFinite,
            (0...1).contains(landmark.position.x),
            (0...1).contains(landmark.position.y)
        else {
            return nil
        }
        return TherapyPoint(x: landmark.position.x * aspect, y: landmark.position.y)
    }
}
