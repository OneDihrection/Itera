//
//  MovementLandmarkSmoother.swift
//  Itera
//
//  Created by dimaswisodewo on 29/10/2026.
//

import Foundation

/// Smooths movement observations before they reach activity geometry or overlays.
struct MovementLandmarkSmoother {
    private var filters: [BodyJoint: JointPositionFilter] = [:]
    private var lastTimestamp: Double?
    private var lastGeneration: UUID?
    private var lastEpoch = 0
    private var imageWidth = 0
    private var imageHeight = 0

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

        // A joint that drops below the confidence floor for a frame or two keeps its filter, so it
        // does not snap back unfiltered when it returns. The filter's own 0.3 s rule still
        // restarts it after a real gap, so nothing is blended across lost evidence.

        let aspect = observation.aspect
        var joints = observation.joints

        for (joint, landmark) in observation.joints {
            guard Self.isUsable(landmark) else {
                continue
            }

            var filter = filters[joint] ?? JointPositionFilter()
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
            cup: observation.cup,
            hand: observation.hand,
            subjectEpoch: observation.subjectEpoch
        )
    }

    private static func isUsable(_ landmark: TrackingObservation.Landmark) -> Bool {
        landmark.confidence.isFinite
            && landmark.confidence >= 0.5
            && landmark.position.x.isFinite
            && landmark.position.y.isFinite
            && (0...1).contains(landmark.position.x)
            && (0...1).contains(landmark.position.y)
    }
}

private struct JointPositionFilter {
    private var previous: TherapyPoint?
    private var filtered: TherapyPoint?
    private var timestamp: Double?
    private var speed = 0.0

    /// Aspect-corrected jump between two raw frames that is treated as a detector swap until the
    /// next frame confirms it. A fast reach moves a wrist about 0.05 between frames.
    private static let outlierDistance = 0.15
    private static let confirmationDistance = 0.06

    /// The last raw sample held back as a possible outlier, or `nil`.
    private var heldBack: TherapyPoint?

    mutating func consume(_ value: TherapyPoint, at time: Double) -> TherapyPoint {
        guard let previous, let filtered, let timestamp,
              time.isFinite, time > timestamp, time - timestamp <= 0.3 else {
            self.previous = value
            self.filtered = value
            self.timestamp = time.isFinite ? time : nil
            speed = 0
            heldBack = nil
            return value
        }

        // A single impossible jump (Vision briefly placing a wrist on the other arm) is held for
        // one frame. If the next frame lands near it, the move was real and is followed; if not,
        // the jump never reaches the drawing or the scoring.
        // Compared with the previous raw sample, not the filtered point, which trails a fast move.
        let isJump = (value - previous).length > Self.outlierDistance
        let confirmsHeldJump = heldBack.map { (value - $0).length <= Self.confirmationDistance } ?? false

        if isJump, !confirmsHeldJump {
            heldBack = value
            self.timestamp = time
            return filtered
        }

        heldBack = nil

        let interval = time - timestamp
        let measuredSpeed = ((value - previous).scaled(1 / interval)).length
        speed += (1 - exp(-interval / 0.1)) * (measuredSpeed - speed)

        let motion = min(1, speed / 0.5)
        let timeConstant = 0.14 - 0.08 * motion
        let result = filtered + (value - filtered).scaled(1 - exp(-interval / timeConstant))

        self.previous = value
        self.filtered = result
        self.timestamp = time
        return result
    }
}
