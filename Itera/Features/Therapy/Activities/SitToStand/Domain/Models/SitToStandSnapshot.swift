//
//  SitToStandSnapshot.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import Foundation

enum SitToStandPhase: Equatable {
    case seatedCapture, trial, returnToSeat, countdown, practice
}

/// Where the body is within one sit-to-stand repetition.
enum SitToStandStage: Equatable {
    case seated, leaning, rising, standing, lowering
}

/// The tracked leg-and-trunk chain on the side facing the camera, in aspect-corrected image units.
struct SitToStandJoints: Equatable {
    var shoulder: TherapyPoint
    var hip: TherapyPoint
    var knee: TherapyPoint
    var ankle: TherapyPoint
}

struct SitToStandSnapshot {
    var phase: SitToStandPhase = .seatedCapture
    var stage: SitToStandStage = .seated
    var instruction = "sts.holdSeated"
    /// Hold progress while capturing a pose; 0 during practice.
    var progress = 0.0
    var count = 0
    var seconds = 5
    /// Knee angle in degrees: about 90 seated, close to 180 standing.
    var kneeAngle = 0.0
    /// Forward trunk lean in degrees from vertical; positive leans toward the knees.
    var trunkLean = 0.0
    /// Calibrated progress from the seated pose (0) to the standing pose (1).
    var rise = 0.0
    /// The forward lean required before rising has been reached for this repetition.
    var leanReached = false
    var joints: SitToStandJoints?
    var aspect = 1.0
    /// A short corrective cue for this repetition, shown in place of the instruction.
    var cue: String?
    var trackingMessage: String?
}
