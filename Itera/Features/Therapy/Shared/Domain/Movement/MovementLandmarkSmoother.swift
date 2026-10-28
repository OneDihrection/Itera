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
    private var imageWidth = 0
    private var imageHeight = 0

    mutating func reset() {
        filters.removeAll(keepingCapacity: true)
        lastTimestamp = nil
        lastGeneration = nil
        imageWidth = 0
        imageHeight = 0
    }

    mutating func consume(_ observation: TrackingObservation) -> TrackingObservation {
        guard observation.personCount == 1,
              observation.timestamp.isFinite,
              observation.width > 0,
              observation.height > 0 else {
            reset()
            return observation
        }

        let discontinuity = observation.generation != lastGeneration
            || observation.width != imageWidth
            || observation.height != imageHeight
            || lastTimestamp.map {
                observation.timestamp <= $0 || observation.timestamp - $0 > 0.3
            } == true

        if discontinuity {
            filters.removeAll(keepingCapacity: true)
        }

        for joint in BodyJoint.allCases {
            if let landmark = observation.joints[joint], Self.isUsable(landmark) {
                continue
            }

            filters[joint] = nil
        }

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
        imageWidth = observation.width
        imageHeight = observation.height

        return TrackingObservation(
            timestamp: observation.timestamp,
            generation: observation.generation,
            width: observation.width,
            height: observation.height,
            personCount: observation.personCount,
            joints: joints,
            cup: observation.cup
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

    mutating func consume(_ value: TherapyPoint, at time: Double) -> TherapyPoint {
        guard let previous, let filtered, let timestamp,
              time.isFinite, time > timestamp, time - timestamp <= 0.3 else {
            self.previous = value
            self.filtered = value
            self.timestamp = time.isFinite ? time : nil
            speed = 0
            return value
        }

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
