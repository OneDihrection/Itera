//
//  BalanceExercise.swift
//  Tuntun
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

extension BalanceExercise {
    /// The kind a saved session uses for this exercise.
    var therapyKind: TherapyKind {
        switch self {
        case .crossMidline: return .crossMidline
        case .externalRotation: return .externalRotation
        case .internalRotation: return .internalRotation
        case .shoulderFlexion: return .shoulderFlexion
        case .sitToStand: return .sitToStand
        }
    }

    init?(kind: TherapyKind) {
        switch kind {
        case .crossMidline: self = .crossMidline
        case .externalRotation: self = .externalRotation
        case .internalRotation: self = .internalRotation
        case .shoulderFlexion: self = .shoulderFlexion
        case .sitToStand: self = .sitToStand
        case .armRaise, .elbowBend, .directionalReach, .foldTowel: return nil
        }
    }
}
