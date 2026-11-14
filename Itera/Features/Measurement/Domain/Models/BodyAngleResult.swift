//
//  BodyAngleResult.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

/// One arm exercise's held angle before practice (calibration) and through practice, saved
/// with each set's result. Ranges are cumulative across the activity's sets so far.
struct BodyAngleResult: Codable, Equatable {
    /// `BodyAngle` raw value, kept as text so an unknown future value never fails decoding.
    let angle: String
    var before: AngleRange?
    var after: AngleRange?
    /// True when every held reading came from Vision 3D joints.
    var threeD: Bool

    var bodyAngle: BodyAngle? { BodyAngle(rawValue: angle) }

    /// Range of motion during practice minus range of motion at calibration.
    var spanChange: Double? {
        guard let before, let after else {
            return nil
        }

        return after.span - before.span
    }
}

extension BodyAngle {
    /// The angle each body exercise reports; other activities report none.
    static func measured(for kind: TherapyKind) -> BodyAngle? {
        switch kind {
        case .armRaise:
            return .shoulderElevation
        case .elbowBend:
            return .elbowFlexion
        case .directionalReach, .cup, .foldTowel, .sitToStand:
            return nil
        }
    }
}

/// Records one body activity's held angle on its configured side.
struct BodyAngleRecorder {
    let angle: BodyAngle
    let side: HandSide
    private var track = StagedAngleTrack()

    init?(kind: TherapyKind, side: TherapySide) {
        guard let angle = BodyAngle.measured(for: kind) else {
            return nil
        }

        self.angle = angle
        self.side = side == .left ? .left : .right
    }

    mutating func observe(_ frame: TrackingObservation, stage: AngleStage) {
        track.consume(JointAngleCalculator.sample(angle, side: side, in: frame), stage: stage)
    }

    mutating func interrupt() {
        track.interrupt()
    }

    var result: BodyAngleResult? {
        guard track.heldAny else {
            return nil
        }

        return BodyAngleResult(angle: angle.rawValue, before: track.before, after: track.after, threeD: track.threeD)
    }
}
