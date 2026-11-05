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

struct TherapyRectangle {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double

    func contains(_ point: TherapyPoint, margin: Double) -> Bool {
        minX.isFinite && minY.isFinite && width.isFinite && height.isFinite
            && width > 0 && height > 0
            && point.x >= minX - margin && point.x <= minX + width + margin
            && point.y >= minY - margin && point.y <= minY + height + margin
    }
}

enum CupTrackingState { case searching, tracking, lost, ambiguous }

struct CupEvidence {
    let timestamp: Double
    let generation: UUID
    let centers: [TherapyPoint]
    var bounds: [TherapyRectangle] = []
    var trackID: UUID? = nil
    var confidence: Float = 0
    var lastDetectionTimestamp: Double? = nil
    var state: CupTrackingState = .searching
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
    let personCount: Int
    let joints: [BodyJoint: Landmark]
    var cup: CupEvidence? = nil
    var hand: HandEvidence? = nil
    var workspaceMirrored = false

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
