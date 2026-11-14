//
//  JointAngle.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

// MARK: - What is measured

/// Body angles named like a goniometer reading: 0° is the anatomical start position.
enum BodyAngle: String, CaseIterable, Identifiable {
    /// 180° minus the shoulder–elbow–wrist angle: 0° with the arm straight.
    case elbowFlexion
    /// The hip–shoulder–elbow angle: 0° with the arm at the side, about 180° overhead. Front-on to
    /// the camera this is closest to abduction; side-on, to flexion.
    case shoulderElevation
    /// 180° minus the hip–knee–ankle angle: 0° with the leg straight.
    case kneeFlexion

    var id: String { rawValue }

    var titleKey: String { "measurement.body.\(rawValue)" }

    /// Proximal joint, vertex, distal joint, for the patient's anatomical side.
    func joints(side: HandSide) -> (BodyJoint, BodyJoint, BodyJoint) {
        let left = side == .left

        switch self {
        case .elbowFlexion:
            return left ? (.leftShoulder, .leftElbow, .leftWrist) : (.rightShoulder, .rightElbow, .rightWrist)
        case .shoulderElevation:
            return left ? (.leftHip, .leftShoulder, .leftElbow) : (.rightHip, .rightShoulder, .rightElbow)
        case .kneeFlexion:
            return left ? (.leftHip, .leftKnee, .leftAnkle) : (.rightHip, .rightKnee, .rightAnkle)
        }
    }

    /// Flexion readings subtract the vertex angle from a straight line; elevation does not.
    var measuresFromStraight: Bool { self != .shoulderElevation }
}

enum MeasuredFinger: Int, CaseIterable, Identifiable {
    case thumb, index, middle, ring, little

    var id: Int { rawValue }

    var titleKey: String {
        ["measurement.finger.thumb", "measurement.finger.index", "measurement.finger.middle",
         "measurement.finger.ring", "measurement.finger.little"][rawValue]
    }

    /// The first joint index in `HandEvidence.points` (thumb CMC or finger MCP).
    var baseIndex: Int { [1, 5, 9, 13, 17][rawValue] }
}

/// The finger joint whose bend is measured. The thumb has no third joint.
enum FingerJointLevel: String, CaseIterable, Identifiable {
    /// MCP: the knuckle (thumb: MP).
    case knuckle
    /// PIP: the middle joint (thumb: IP).
    case middle
    /// DIP: the end joint. Not available for the thumb.
    case end

    var id: String { rawValue }

    var titleKey: String { "measurement.joint.\(rawValue)" }
}

enum HandAngle: Hashable {
    /// 180° minus the joint's angle between its two bones: 0° with the finger straight.
    case flexion(MeasuredFinger, FingerJointLevel)
    /// The angle between the index and little finger proximal bones: spreading the fingers.
    case spread
}

// MARK: - Results

enum AngleSource: Equatable {
    /// From 2D image points: accurate only when the movement is parallel to the screen.
    case image2D
    /// From metric 3D joints (Vision 3D body or MediaPipe hand world landmarks).
    case world3D
}

struct AngleSample: Equatable {
    let degrees: Double
    let source: AngleSource
    let timestamp: Double
    /// Unmirrored normalized image points (origin bottom-left) of the measured joints, in drawing
    /// order, for the overlay.
    let points: [TherapyPoint]
}
