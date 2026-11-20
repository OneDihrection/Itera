//
//  SitToStandSnapshot.swift
//  Tuntun
//
//  Created by Fauzan Azima on 03/11/2026.
//

import Foundation

enum SitToStandPhase: Equatable {
    case seatedCapture, trial, returnToSeat, countdown, practice
}

/// Where the body is within one sit-to-stand repetition.
enum SitToStandStage: Equatable {
    case seated, rising, standing, lowering
}

/// The tracked trunk-and-thigh chain on the side facing the camera, in aspect-corrected image
/// units. The camera frames the seated patient down to the knees, so no ankle is tracked.
struct SitToStandJoints: Equatable {
    var shoulder: TherapyPoint
    var hip: TherapyPoint
    var knee: TherapyPoint
}

/// The arrow for the patient's next move, in aspect-corrected image units: it runs from `tail` to
/// `tip` and is fixed to the calibrated poses, while `joint` moves along it.
struct SitToStandGuide: Equatable {
    var tail: TherapyPoint
    var tip: TherapyPoint
    var joint: TherapyPoint
}

struct SitToStandSnapshot {
    var phase: SitToStandPhase = .seatedCapture
    var stage: SitToStandStage = .seated
    var instruction = "sts.holdSeated"
    /// Hold progress while capturing a pose; 0 during practice.
    var progress = 0.0
    var count = 0
    var seconds = 5
    /// Shoulder–hip–knee angle in degrees: about 90 seated upright, close to 180 standing.
    var hipAngle = 0.0
    /// Forward trunk lean in degrees from vertical; positive leans toward the knees.
    var trunkLean = 0.0
    /// Calibrated progress from the seated pose (0) to the standing pose (1).
    var rise = 0.0
    /// How far through the current half of a repetition the patient is, 0...1: rising to the
    /// stand, then sitting back down. Each half starts empty.
    var repetitionProgress = 0.0
    /// False once this repetition can no longer count, or while waiting for the seat.
    var repetitionCounts = true
    /// The next move during the trial and practice; nil during holds and the countdown.
    var guide: SitToStandGuide?
    /// Counts every milestone that pops the hip circle: the seated and standing calibration
    /// holds, each stand in practice and each counted repetition. It only grows.
    var completions = 0
    var joints: SitToStandJoints?
    var aspect = 1.0
    /// A short corrective cue for this repetition, shown in place of the instruction.
    var cue: String?
    var trackingMessage: String?
}
