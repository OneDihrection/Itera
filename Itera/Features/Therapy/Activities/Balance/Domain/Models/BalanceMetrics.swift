//
//  BalanceMetrics.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import Foundation

struct BalanceMetrics: Codable, Equatable {
    var midlineDwellTime = 0.0
    var compensationEventsCount = 0
    var pathSmoothness = 1.0
    var completedTouches = 0
}

struct TrunkCompensation: Equatable {
    enum Reason: String, CaseIterable {
        case lateralLean
        case lateralShift
        case shoulderRotation
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
}

struct BalanceSnapshot: Equatable {
    enum Phase: Equatable {
        case findingBody
        case calibrating
        case reaching
        case holding
        case returning
        case complete
    }

    var phase: Phase = .findingBody
    var instructionKey = "balance.tracking"
    var calibrationProgress = 0.0
    var activeArm: CrossingArm = .right
    var armSelection: BalanceArmSelection = .both
    var metrics = BalanceMetrics()
    var compensation = TrunkCompensation()
    var overlay: BalanceOverlay?
    var goal = 6
    var holdDuration = 10.0
}
