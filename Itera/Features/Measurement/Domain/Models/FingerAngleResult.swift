//
//  FingerAngleResult.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

/// A finger angle reported for an exercise. Four-finger metrics average the index, middle,
/// ring and little fingers, so one occluded finger blanks the frame instead of skewing it.
enum FingerAngleMetric: String, CaseIterable, Identifiable {
    /// MCP flexion: bending at the knuckles. Low values show extension.
    case knuckleFlexion
    /// PIP flexion: bending at the middle joints.
    case middleFlexion
    /// DIP flexion: bending at the end joints.
    case endFlexion
    /// Mean of the thumb MP and IP flexion.
    case thumbFlexion
    /// Angle between the index and little finger proximal bones.
    case spread

    var id: String { rawValue }

    var titleKey: String { "report.angle.\(rawValue)" }

    /// The angles each part averages.
    var parts: [HandAngle] {
        let fingers: [MeasuredFinger] = [.index, .middle, .ring, .little]

        switch self {
        case .knuckleFlexion:
            return fingers.map { .flexion($0, .knuckle) }
        case .middleFlexion:
            return fingers.map { .flexion($0, .middle) }
        case .endFlexion:
            return fingers.map { .flexion($0, .end) }
        case .thumbFlexion:
            return [.flexion(.thumb, .knuckle), .flexion(.thumb, .middle)]
        case .spread:
            return [.spread]
        }
    }

    /// What each exercise moves. Forearm rotation turns the wrist, not a finger joint, so it
    /// reports no finger angle.
    static func metrics(for exercise: FingerExercise) -> [FingerAngleMetric] {
        switch exercise {
        case .fullFist:
            return [.knuckleFlexion, .middleFlexion]
        case .hookFist:
            return [.middleFlexion, .endFlexion]
        case .opposition:
            return [.thumbFlexion]
        case .spreading:
            return [.spread]
        case .extensionSequence:
            return [.knuckleFlexion, .middleFlexion]
        case .forearmRotation:
            return []
        }
    }
}

/// The smallest and largest held angle in one stage, in degrees.
struct AngleRange: Codable, Equatable {
    let minimum: Double
    let maximum: Double

    var span: Double { maximum - minimum }

    func including(_ other: AngleRange?) -> AngleRange {
        guard let other else {
            return self
        }

        return AngleRange(minimum: min(minimum, other.minimum), maximum: max(maximum, other.maximum))
    }
}

/// One exercise's held angles before practice (calibration) and during practice to its end.
struct FingerAngleResult: Equatable, Identifiable {
    let metric: FingerAngleMetric
    var before: AngleRange?
    var after: AngleRange?
    /// True when every held reading came from metric 3D landmarks (MediaPipe); 2D readings
    /// shrink when fingers bend toward the camera, so the report labels them.
    var threeD: Bool

    var id: String { metric.rawValue }

    /// Range of motion during practice minus range of motion at calibration.
    var spanChange: Double? {
        guard let before, let after else {
            return nil
        }

        return after.span - before.span
    }
}
