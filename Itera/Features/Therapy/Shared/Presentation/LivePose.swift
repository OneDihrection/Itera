//
//  LivePose.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import CoreGraphics

/// The patient's skeleton drawn straight from tracking, before any exercise engine accepts frames.
///
/// Engines draw their own overlay only once calibration guidance, countdowns and their geometry
/// checks allow it, which can take several seconds after the camera starts. This guide shows the
/// tracked body from the first frame so the patient sees at once that they are being followed.
struct LivePose {
    /// One frame's skeleton and the image shape it is drawn in.
    struct Skeleton {
        let guide: SessionPoseGuide
        /// Width over height of the camera image.
        let aspect: Double

        var imageSize: CGSize {
            CGSize(width: aspect, height: 1)
        }
    }

    /// Matches the Balance engines' floor, so the skeleton appears as soon as joints are plausible.
    private static let minimumConfidence: Float = 0.2

    private var smoother = MovementLandmarkSmoother(minimumConfidence: Self.minimumConfidence)

    mutating func reset() {
        smoother.reset()
    }

    /// - Returns: the skeleton in normalized image coordinates, or `nil` without one clear patient
    ///   whose shoulders are visible.
    mutating func skeleton(for frame: TrackingObservation) -> Skeleton? {
        let smoothed = smoother.consume(frame)

        guard smoothed.personCount == 1,
              let leftShoulder = Self.point(.leftShoulder, in: smoothed),
              let rightShoulder = Self.point(.rightShoulder, in: smoothed) else {
            return nil
        }

        let leftHip = Self.point(.leftHip, in: smoothed)
        let rightHip = Self.point(.rightHip, in: smoothed)

        var torso: [CGPoint] = []
        if let leftHip, let rightHip {
            torso = [leftShoulder, rightShoulder, rightHip, leftHip]
        }

        let limbs: [[CGPoint]] = [
            Self.limb(from: leftShoulder, through: [.leftElbow, .leftWrist], in: smoothed),
            Self.limb(from: rightShoulder, through: [.rightElbow, .rightWrist], in: smoothed),
            Self.limb(from: leftHip, through: [.leftKnee, .leftAnkle], in: smoothed),
            Self.limb(from: rightHip, through: [.rightKnee, .rightAnkle], in: smoothed),
        ]

        let guide = SessionPoseGuide(
            torso: torso,
            limbs: limbs,
            emphasis: .ambient
        )
        return Skeleton(guide: guide, aspect: smoothed.aspect)
    }

    // MARK: - Joints

    private static func point(_ joint: BodyJoint, in frame: TrackingObservation) -> CGPoint? {
        guard let point = frame.point(joint, minimumConfidence: minimumConfidence) else {
            return nil
        }

        return CGPoint(x: point.x / frame.aspect, y: point.y)
    }

    /// The joints after `start` up to the first one not seen, so a limb never skips a gap.
    private static func limb(
        from start: CGPoint?,
        through joints: [BodyJoint],
        in frame: TrackingObservation
    ) -> [CGPoint] {
        guard let start else {
            return []
        }

        var chain = [start]
        for joint in joints {
            guard let next = point(joint, in: frame) else {
                break
            }

            chain.append(next)
        }
        return chain
    }
}
