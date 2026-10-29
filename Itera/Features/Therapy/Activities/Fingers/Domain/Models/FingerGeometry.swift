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
            return [0, 9] + bases.flatMap { [$0, $0 + 1, $0 + 2] }
        case .opposition:
            return [0, 9, 4, bases[finger] + 3]
        case .spreading:
            return [0, 9, 8, 12, 16, 20]
        case .extensionSequence:
            let base = bases[finger]
            return [0, 9, base, base + 1, base + 2]
        }
    }

    /// Dimensionless visible-motion metrics; these are not grip force or clinical joint angles.
    func metric(for exercise: FingerExercise, finger: Int) -> Double? {
        guard points.count == 21, (0..<4).contains(finger),
              requiredJoints(for: exercise, finger: finger).allSatisfy({
                  points[$0].confidence >= 0.5 && points[$0].x.isFinite && points[$0].y.isFinite
              }),
              width > 0, height > 0,
              distance(0, 9) > 0.04 else { return nil }
        let palm = distance(0, 9)
        let bases = [5, 9, 13, 17]
        switch exercise {
        case .fullFist:
            return bases.map { (180 - angle($0, $0 + 1, $0 + 2)) / 180 }.reduce(0, +) / 4
        case .hookFist:
            let knuckles = bases.map { angle(0, $0, $0 + 1) }.reduce(0, +) / 4
            guard knuckles > 125 else {
                return nil
            }
            return bases.map { (180 - angle($0, $0 + 1, $0 + 2)) / 180 }.reduce(0, +) / 4
        case .opposition:
            return -distance(4, bases[finger] + 3) / palm
        case .spreading:
            return (distance(8, 12) + distance(12, 16) + distance(16, 20)) / palm
        case .extensionSequence:
            let base = bases[finger]
            return angle(base, base + 1, base + 2) / 180
        }
    }
}
