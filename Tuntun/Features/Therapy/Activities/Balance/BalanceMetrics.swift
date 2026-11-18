//
//  BalanceMetrics.swift
//  Tuntun
//
//  Created by Gracia A on 02/11/2026.
//

import Foundation

extension BalanceExercise {
    /// The direction the forearm travels from the resting pose.
    var rotationDirection: RotationDirection { self == .internalRotation ? .inward : .outward }
}

extension BalanceArmSelection {
    var initialArm: CrossingArm {
        self == .left ? .left : .right
    }

    func arm(after completedArm: CrossingArm) -> CrossingArm {
        switch self {
        case .right: .right
        case .left: .left
        case .both: completedArm.next
        }
    }
}

extension CrossingArm {
    var therapySide: TherapySide { self == .left ? .left : .right }
}

enum RotationDirection {
    /// Away from the body: external rotation.
    case outward
    /// Toward the belly: internal rotation.
    case inward
}

/// What the Balancing view model needs from a movement engine.
protocol BalanceMovementEngine {
    var snapshot: BalanceSnapshot { get }
    /// The camera frame in points, so bubbles keep the shared on-screen size.
    var viewport: TherapyViewport? { get set }
    mutating func consume(_ frame: TrackingObservation, scoringEnabled: Bool)
    mutating func invalidateCalibration()
    mutating func restart()
    /// Starts another set with the same calibration: the count and per-repetition state reset,
    /// while the captured starting position and targets are kept.
    mutating func nextSet()
}

struct BalanceMetrics: Codable, Equatable {
    var midlineDwellTime = 0.0
    var compensationEventsCount = 0
    var pathSmoothness = 1.0
    var completedTouches = 0
    /// Largest estimated forearm rotation seen, in degrees (external rotation only).
    var peakRotation = 0.0
}

struct TrunkCompensation: Equatable {
    enum Reason: String, CaseIterable {
        case lateralLean
        case lateralShift
        case shoulderRotation
        case elbowAway
    }

    var leanDegrees = 0.0
    var lateralShiftRatio = 0.0
    var shoulderRotationRatio = 0.0
    var index = 0.0
    var reasons: Set<Reason> = []

    var isCompensating: Bool { !reasons.isEmpty }
}

enum CrossingArm: String, Equatable, Hashable {
    case left
    case right

    var wrist: BodyJoint { self == .left ? .leftWrist : .rightWrist }
    var ownShoulder: BodyJoint { self == .left ? .leftShoulder : .rightShoulder }
    var targetShoulder: BodyJoint { self == .left ? .rightShoulder : .leftShoulder }
    var next: CrossingArm { self == .left ? .right : .left }
}

struct BalanceOverlay: Equatable {
    let aspect: Double
    let midlineBase: TherapyPoint
    let midlineTop: TherapyPoint
    let leftShoulder: TherapyPoint
    let rightShoulder: TherapyPoint
    let leftHip: TherapyPoint
    let rightHip: TherapyPoint
    let wrist: TherapyPoint?
    let target: TherapyPoint?
    let isReturnTarget: Bool
    let targetRadius: Double
    let crossedMidline: Bool
    let targetProgress: Double
    let holdSecondsRemaining: Int?
    let compensationWarning: Bool
    /// Shoulder, elbow, and wrist of the working arm, drawn when the movement is an arm rotation.
    var armChain: [TherapyPoint] = []
    /// The target marker is the patient's own wrist, held still during end-pose calibration.
    var isCalibrationHold = false
    /// Where the wrist should head while the comfortable end is calibrated; nil hides the cue.
    var calibrationTip: TherapyPoint? = nil
    /// Where the calibration cue starts: the wrist's resting position, fixed to the body so the
    /// cue stays put while the wrist moves through it.
    var calibrationTail: TherapyPoint? = nil
}

struct BalanceSnapshot: Equatable {
    enum Phase: Equatable {
        case findingBody
        case calibrating
        /// The patient shows how far they can comfortably turn; that becomes their target.
        case calibratingRange
        case reaching
        case holding
        case returning
        case complete
    }

    var phase: Phase = .findingBody
    var instructionKey = "balance.tracking"
    var calibrationProgress = 0.0
    /// Seconds left of the end-pose hold during calibration; `nil` until the patient holds still.
    var calibrationCountdown: Int?
    var activeArm: CrossingArm = .right
    var armSelection: BalanceArmSelection = .both
    var metrics = BalanceMetrics()
    var compensation = TrunkCompensation()
    var overlay: BalanceOverlay?
    var goal = 6
    var holdDuration = 10.0
    /// Estimated forearm rotation right now, in degrees (external rotation only).
    var rotationDegrees = 0.0
    /// The patient's own calibrated target for the working arm, in degrees (rotations only).
    var targetAngle = 0
    /// Live hip angle and forward trunk lean, in degrees (sit-to-stand only).
    var hipAngle = 0.0
    var trunkLean = 0.0
}
