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
        }
    }

    /// Dimensionless visible-motion metrics; these are not grip force or clinical joint angles.
    func metric(for exercise: FingerExercise, finger: Int) -> Double? {
        guard points.count == 21, (0..<4).contains(finger),
              requiredJoints(for: exercise, finger: finger).allSatisfy({
                  points[$0].confidence >= 0.5 && points[$0].x.isFinite && points[$0].y.isFinite
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
        }
    }
}
