//
//  JointAngleCalculator.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

/// Computes joint angles from one frame. Metric 3D joints are preferred because they do not
/// shrink when the limb points toward the camera; 2D image points are the fallback.
enum JointAngleCalculator {
    /// The confidence every exercise requires of its joints (SYSTEM_DESIGN section 6).
    static let minimumConfidence: Float = 0.5

    // MARK: - Body

    static func sample(
        _ angle: BodyAngle,
        side: HandSide,
        in observation: TrackingObservation
    ) -> AngleSample? {
        let (a, b, c) = angle.joints(side: side)

        guard let pa = observation.point(a, minimumConfidence: minimumConfidence),
              let pb = observation.point(b, minimumConfidence: minimumConfidence),
              let pc = observation.point(c, minimumConfidence: minimumConfidence) else {
            return nil
        }

        let drawn = [a, b, c].compactMap { observation.joints[$0]?.position }
        let source: AngleSource
        let vertex: Double?

        if let wa = observation.world[a], let wb = observation.world[b], let wc = observation.world[c] {
            source = .world3D
            vertex = Self.angle(wa, wb, wc)
        } else {
            source = .image2D
            vertex = Self.angle(pa, pb, pc)
        }

        guard let vertex else {
            return nil
        }

        return AngleSample(
            degrees: angle.measuresFromStraight ? 180 - vertex : vertex,
            source: source,
            timestamp: observation.timestamp,
            points: drawn
        )
    }

    // MARK: - Hand

    static func sample(_ angle: HandAngle, in hand: HandEvidence) -> AngleSample? {
        guard hand.points.count == 21 else {
            return nil
        }

        switch angle {
        case .flexion(let finger, let level):
            guard let (a, b, c) = flexionJoints(finger, level) else {
                return nil
            }

            return handSample(indices: [a, b, c], in: hand) { points in
                Self.angle(points[0], points[1], points[2]).map { 180 - $0 }
            }
        case .spread:
            // Index MCP→PIP against little MCP→PIP; drawn as one connected line.
            return handSample(indices: [6, 5, 17, 18], in: hand) { points in
                Self.angle(between: points[1], points[0], and: points[2], points[3])
            }
        }
    }

    /// Joint indices (proximal, vertex, distal) in `HandEvidence.points` order.
    static func flexionJoints(_ finger: MeasuredFinger, _ level: FingerJointLevel) -> (Int, Int, Int)? {
        let base = finger.baseIndex

        if finger == .thumb {
            switch level {
            case .knuckle:
                return (1, 2, 3)
            case .middle:
                return (2, 3, 4)
            case .end:
                return nil
            }
        }

        switch level {
        case .knuckle:
            return (0, base, base + 1)
        case .middle:
            return (base, base + 1, base + 2)
        case .end:
            return (base + 1, base + 2, base + 3)
        }
    }

    /// Measures in 3D when the hand has world landmarks, otherwise in aspect-corrected 2D.
    private static func handSample(
        indices: [Int],
        in hand: HandEvidence,
        measure: ([Vector]) -> Double?
    ) -> AngleSample? {
        guard indices.allSatisfy({ hand.points[$0].confidence >= minimumConfidence }) else {
            return nil
        }

        let aspect = hand.width / max(hand.height, 1)
        let drawn = indices.map { TherapyPoint(x: hand.points[$0].x, y: hand.points[$0].y) }
        let source: AngleSource
        let vectors: [Vector]

        if let world = hand.world, world.count == hand.points.count {
            source = .world3D
            vectors = indices.map { world[$0] }
        } else {
            source = .image2D
            vectors = indices.map { Vector(x: hand.points[$0].x * aspect, y: hand.points[$0].y, z: 0) }
        }

        guard let degrees = measure(vectors), degrees.isFinite else {
            return nil
        }

        return AngleSample(degrees: degrees, source: source, timestamp: hand.timestamp, points: drawn)
    }

    // MARK: - Geometry

    /// 2D and 3D share one vector type; 2D points use z = 0.
    typealias Vector = TherapyVector3

    /// The angle at `b` between `a` and `c`, in degrees, or nil when a bone is too short to aim.
    static func angle(_ a: TherapyPoint, _ b: TherapyPoint, _ c: TherapyPoint) -> Double? {
        angle(Vector(x: a.x, y: a.y, z: 0), Vector(x: b.x, y: b.y, z: 0), Vector(x: c.x, y: c.y, z: 0))
    }

    static func angle(_ a: Vector, _ b: Vector, _ c: Vector) -> Double? {
        angle(between: b, a, and: b, c)
    }

    /// The angle between the directions `from1 → to1` and `from2 → to2`, in degrees.
    static func angle(between from1: Vector, _ to1: Vector, and from2: Vector, _ to2: Vector) -> Double? {
        let u = to1 - from1
        let v = to2 - from2
        let length = u.length * v.length

        guard u.isFinite, v.isFinite, length > 1e-9 else {
            return nil
        }

        return acos(max(-1, min(1, u.dot(v) / length))) * 180 / .pi
    }
}
