//
//  BalanceMetrics.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import Foundation

/// The body-tracked practices that share the Balancing screens: setup, live session, and summary.
enum BalanceExercise: String, Hashable {
    case crossMidline
    case externalRotation
    case internalRotation
    /// Arm raised forward with the palm turned up and the arm rotated outward (Arm Rotation).
    case shoulderFlexion
    /// Sit-to-stand with a controlled forward trunk lean (Trunk Control), seen from the side.
    case sitToStand

    /// True for the arm movements measured as an estimated angle rather than a midline crossing.
    var isRotation: Bool {
        switch self {
        case .externalRotation, .internalRotation, .shoulderFlexion: return true
        case .crossMidline, .sitToStand: return false
        }
    }

    var isSitToStand: Bool { self == .sitToStand }

    /// The direction the forearm travels from the resting pose.
    var rotationDirection: RotationDirection { self == .internalRotation ? .inward : .outward }

    /// Strings that differ for internal rotation; every other rotation string is shared.
    private static let internalSpecific: Set<String> = [
        "title", "overview", "animationHint", "animationAccessibility", "step.touch",
        "step.touch.detail", "begin", "rotateRight", "rotateLeft", "voice.rightTarget",
        "voice.leftTarget",
        "calibration.endHint", "calibrateRange",
    ]

    /// String-catalog key. Balancing keeps its original `balance.` keys; both rotations share the
    /// `rotation.` strings except the ones that describe the direction.
    private static let flexionSpecific: Set<String> = [
        "title", "subtitle", "overview", "animationHint", "animationAccessibility", "cameraAccessibility",
        "step.posture", "step.posture.detail", "step.touch", "step.touch.detail", "step.balance.detail",
        "begin", "rotateRight", "rotateLeft", "elbowAtSide", "calibrateRange", "compensationWarning",
        "return", "complete", "completion.subtitle", "metric.angle", "summary.peak", "repetitions",
        "repetitionsHint", "touchUnit", "metric.touches", "targetCalibrated", "voice.rightTarget",
        "voice.leftTarget", "voice.complete", "voice.returnAndSwitch", "voice.returnSameSide",
    ]

    /// Strings written for sit-to-stand; any other name falls back to the shared `balance.` text.
    private static let sitToStandSpecific: Set<String> = [
        "title", "subtitle", "overview", "animationHint", "animationAccessibility", "cameraAccessibility",
        "step.posture", "step.posture.detail", "step.touch", "step.touch.detail", "step.balance",
        "step.balance.detail", "begin", "repetitions", "repetitionsHint", "touchUnit", "metric.touches",
        "completion.subtitle", "tracking", "voice.complete", "voice.returnSameSide", "voice.rightTarget",
        "voice.leftTarget",
    ]

    func key(_ name: String) -> String {
        switch self {
        case .crossMidline: return "balance." + name
        case .sitToStand:
            return (Self.sitToStandSpecific.contains(name) ? "sitToStand." : "balance.") + name
        case .externalRotation: return "rotation." + name
        case .shoulderFlexion:
            return (Self.flexionSpecific.contains(name) ? "shoulderFlexion." : "rotation.") + name
        case .internalRotation:
            return (Self.internalSpecific.contains(name) ? "internalRotation." : "rotation.") + name
        }
    }

    /// Settings are remembered per exercise; Balancing keeps its original keys.
    func storageKey(_ name: String) -> String {
        self == .crossMidline ? "balance." + name : rawValue + "." + name
    }
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
    mutating func consume(_ frame: TrackingObservation, scoringEnabled: Bool)
    mutating func invalidateCalibration()
    mutating func restart()
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

enum BalanceArmSelection: String, CaseIterable, Hashable {
    case right
    case left
    case both

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
    var showsMidline = true
    /// The target marker is the patient's own wrist, held still during end-pose calibration.
    var isCalibrationHold = false
    /// Whether the shoulder-hip box is drawn; a side-on chain of joints does not use it.
    var showsTorso = true
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
    /// Live knee angle and forward trunk lean, in degrees (sit-to-stand only).
    var kneeAngle = 0.0
    var trunkLean = 0.0
}
