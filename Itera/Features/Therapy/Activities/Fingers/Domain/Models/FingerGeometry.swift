//
//  FingerGeometry.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

extension HandEvidence {
    // Confidence remains unchanged; an occluded unused finger need not block the movement.
    private func requiredJoints(for exercise: FingerExercise, finger: Int) -> [Int] {
        let bases = [5, 9, 13, 17]
        switch exercise {
        case .fullFist, .hookFist:
            return [0]
        case .opposition:
            return [0, 9, 4, bases[finger] + 3]
        case .spreading:
            return [0, 9, 8, 12, 16, 20]
        case .extensionSequence:
            let base = bases[finger]
            // The selected fingertip must also be visible to present its completion ring.
            return [0, base, base + 1, base + 2, base + 3]
        case .forearmRotation:
            // The wrist, palm axis, and both outer knuckles define how far the palm faces the camera.
            return [0, 5, 9, 17]
        }
    }

    /// Signed apparent palm width relative to palm length: near zero with the thumb side toward
    /// the camera, and positive or negative as the palm or the back of the hand turns toward it.
    ///
    /// The sign deliberately does not depend on which hand it is. A palm and the back of the
    /// opposite hand look alike in a 2D silhouette, and Vision's chirality, a mirrored camera
    /// buffer and the way the patient turns all flip it, so `FingerActivity` learns which sign
    /// the patient's turn produces while calibrating the target pose.
    private func palmFacing() -> Double? {
        let aspect = width / height
        let axisX = (points[9].x - points[0].x) * aspect
        let axisY = points[9].y - points[0].y
        let palmLength = hypot(axisX, axisY)
        guard palmLength > 0.04 else {
            return nil
        }
        let knuckleX = (points[5].x - points[17].x) * aspect
        let knuckleY = points[5].y - points[17].y
        // Component of the index-to-little knuckle line across the palm axis.
        let across = (knuckleX * axisY - knuckleY * axisX) / palmLength
        return across / palmLength
    }

    /// Lowest confidence a required joint may have.
    ///
    /// A turning palm hides its outer knuckles briefly, so forearm rotation accepts them at a
    /// lower confidence instead of dropping the hand mid-turn. Touching fingertips overlap in the
    /// image, which lowers Vision's confidence in exactly the two tips opposition measures, so
    /// those two joints get the same allowance. Every other joint stays at 0.5.
    private func minimumConfidence(for joint: Int, exercise: FingerExercise, finger: Int) -> Float {
        switch exercise {
        case .forearmRotation:
            return 0.3
        case .opposition where joint == 4 || joint == [5, 9, 13, 17][finger] + 3:
            return 0.3
        default:
            return 0.5
        }
    }

    /// Dimensionless visible-motion metrics; these are not grip force or clinical joint angles.
    func metric(for exercise: FingerExercise, finger: Int) -> Double? {
        guard points.count == 21, (0..<4).contains(finger),
              requiredJoints(for: exercise, finger: finger).allSatisfy({
                  points[$0].confidence >= minimumConfidence(for: $0, exercise: exercise, finger: finger)
                      && points[$0].x.isFinite
                      && points[$0].y.isFinite
              }),
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let bases = [5, 9, 13, 17]
        let isGrip = exercise == .fullFist || exercise == .hookFist
        let visibleBases = isGrip ? bases.filter { base in
            [base, base + 1, base + 2].allSatisfy {
                points[$0].confidence >= 0.5 && points[$0].x.isFinite && points[$0].y.isFinite
            } && angle(base, base + 1, base + 2).isFinite
        } : []
        // A fist naturally occludes some fingers. Require two usable chains, never infer hidden ones.
        if isGrip && visibleBases.count < 2 {
            return nil
        }
        let palm: Double
        if isGrip {
            palm = visibleBases.map { distance(0, $0) }.reduce(0, +) / Double(visibleBases.count)
        } else if exercise == .extensionSequence {
            palm = distance(0, bases[finger])
        } else {
            palm = distance(0, 9)
        }
        guard palm > 0.04 else {
            return nil
        }
        switch exercise {
        case .fullFist:
            return visibleBases.map { (180 - angle($0, $0 + 1, $0 + 2)) / 180 }.reduce(0, +) / Double(visibleBases.count)
        case .hookFist:
            let knuckles = visibleBases.map { angle(0, $0, $0 + 1) }.reduce(0, +) / Double(visibleBases.count)
            guard knuckles > 125 else {
                return nil
            }
            return visibleBases.map { (180 - angle($0, $0 + 1, $0 + 2)) / 180 }.reduce(0, +) / Double(visibleBases.count)
        case .opposition:
            return -distance(4, bases[finger] + 3) / palm
        case .spreading:
            return (distance(8, 12) + distance(12, 16) + distance(16, 20)) / palm
        case .extensionSequence:
            let base = bases[finger]
            // Extension may happen at either joint; a straight PIP must not hide DIP movement.
            let middleJoint = angle(base, base + 1, base + 2)
            let tipJoint = angle(base + 1, base + 2, base + 3)
            return (middleJoint + tipJoint) / 360
        case .forearmRotation:
            return palmFacing()
        }
    }
}
