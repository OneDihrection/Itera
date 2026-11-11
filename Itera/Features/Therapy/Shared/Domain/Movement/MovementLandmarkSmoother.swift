//
//  MovementLandmarkSmoother.swift
//  Itera
//
//  Created by dimaswisodewo on 29/10/2026.
//

import Foundation

/// Smooths movement observations before they reach activity geometry or overlays.
struct MovementLandmarkSmoother {
    private let minimumConfidence: Float
    private let limbMinimumConfidence: Float
    private var filters: [BodyJoint: JointSmoothingState] = [:]
    private var lastTimestamp: Double?
    private var lastGeneration: UUID?
    private var lastEpoch = 0
    private var imageWidth = 0
    private var imageHeight = 0

    /// Joints below their confidence floor are not filtered, so a floor lower than the activity's
    /// own acceptance floor lets weak joints flip between filtered and raw. Pass the same floors
    /// the activity accepts; elbows and wrists may use a lower one because they are foreshortened.
    init(minimumConfidence: Float = 0.5, limbMinimumConfidence: Float? = nil) {
        self.minimumConfidence = minimumConfidence
        self.limbMinimumConfidence = limbMinimumConfidence ?? minimumConfidence
    }

    mutating func reset() {
        filters.removeAll(keepingCapacity: true)
        lastTimestamp = nil
        lastGeneration = nil
        lastEpoch = 0
        imageWidth = 0
        imageHeight = 0
    }

    mutating func consume(_ observation: TrackingObservation) -> TrackingObservation {
        guard observation.timestamp.isFinite,
              observation.width > 0,
              observation.height > 0 else {
            reset()
            return observation
        }

        // A frame without a selected patient passes through untouched. Filters survive a short gap
        // (the timestamp rule below clears them after 0.3 s), so a one-frame miss does not make the
        // next frame restart unfiltered.
        guard observation.personCount == 1 else {
            return observation
        }

        // A different locked person must never be blended with the previous one.
        let discontinuity = observation.subjectEpoch != lastEpoch
            || observation.generation != lastGeneration
            || observation.width != imageWidth
            || observation.height != imageHeight
            || lastTimestamp.map {
                observation.timestamp <= $0 || observation.timestamp - $0 > 0.3
            } == true

        if discontinuity {
            filters.removeAll(keepingCapacity: true)
        }

        let aspect = observation.aspect
        var joints = observation.joints

        for (joint, landmark) in observation.joints {
            guard isUsable(landmark, joint: joint) else {
                continue
            }

            var filter = filters[joint] ?? JointSmoothingState()
            let position = filter.consume(
                TherapyPoint(
                    x: landmark.position.x * aspect,
                    y: landmark.position.y
                ),
                at: observation.timestamp
            )
            filters[joint] = filter
            joints[joint] = TrackingObservation.Landmark(
                position: TherapyPoint(x: position.x / aspect, y: position.y),
                confidence: landmark.confidence
            )
        }

        lastTimestamp = observation.timestamp
        lastGeneration = observation.generation
        lastEpoch = observation.subjectEpoch
        imageWidth = observation.width
        imageHeight = observation.height

        return TrackingObservation(
            timestamp: observation.timestamp,
            generation: observation.generation,
            width: observation.width,
            height: observation.height,
            personCount: observation.personCount,
            joints: joints,
            subjectEpoch: observation.subjectEpoch
        )
    }

    private func isUsable(_ landmark: TrackingObservation.Landmark, joint: BodyJoint) -> Bool {
        let floor: Float

        switch joint {
        case .leftElbow, .rightElbow, .leftWrist, .rightWrist:
            floor = limbMinimumConfidence
        default:
            floor = minimumConfidence
        }

        return landmark.confidence.isFinite
            && landmark.confidence >= floor
            && landmark.position.x.isFinite
            && landmark.position.y.isFinite
            && (0...1).contains(landmark.position.x)
            && (0...1).contains(landmark.position.y)
    }
}

/// Keeps the One Euro estimate through brief confidence loss and rejects an isolated detector jump.
private struct JointSmoothingState {
    private var filter = OneEuroFilter(parameters: .bodyJoint)
    private var previousRaw: TherapyPoint?
    private var previousOutput: TherapyPoint?
    private var previousTimestamp: Double?
    private var heldJump: TherapyPoint?

    private static let outlierDistance = 0.15
    private static let confirmationDistance = 0.06

    mutating func consume(_ value: TherapyPoint, at time: Double) -> TherapyPoint {
        if let previousTimestamp, time - previousTimestamp > 0.3 {
            self = JointSmoothingState()
        }

        if let previousRaw, let previousOutput {
            let isJump = (value - previousRaw).length > Self.outlierDistance
            let confirmsJump = heldJump.map {
                (value - $0).length <= Self.confirmationDistance
            } ?? false

            if isJump && !confirmsJump {
                heldJump = value
                return previousOutput
            }
        }

        heldJump = nil
        let output = filter.consume(value, at: time)
        previousRaw = value
        previousOutput = output
        previousTimestamp = time
        return output
    }
}
