//
//  BalanceScriptGuidance.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 23/11/2026.
//

import Foundation

/// One recorded repetition of a 2026-11-23 Balancing script. Keys are full catalog keys.
struct BalanceScriptRepetition {
    /// Spoken before the target: the start pose, or (for the arm scripts) the way back to it.
    var start: [String] = []
    var target: String
    /// Sit to stand only: the cue back to the seat after the stand.
    var back: String? = nil
}

/// One Balancing exercise's 2026-11-23 script (see Documentation/LeftScriptsNarration.md).
struct BalanceScript {
    /// "Selanjutnya kita akan latihan …" and "Latihan ini membantu melatih …".
    let introduction: [String]
    /// Sit to stand's chair and camera notes, after the safety note.
    var introNotes: [String] = []
    /// Phase 1: how to sit or stand and what the camera must see.
    let setup: [String]
    /// Once the body is in view: the confirmation and phase 2's opening.
    let detected: [String]
    /// Repeated while the body is not in view.
    let notVisible: String
    let calibrationStart: [String]
    /// Empty when the exercise captures no end pose (cross midline).
    let calibrationTarget: [String]
    /// Sit to stand's cue back to the seat during calibration.
    var calibrationReturn: [String] = []
    /// Spoken once calibration is complete, before the countdown.
    let calibrationEnding: [String]
    /// The first set's recorded repetitions one to five.
    let firstSet: [BalanceScriptRepetition]
    /// Later sets' recorded repetitions one to three.
    let laterSets: [BalanceScriptRepetition]
    /// Praise after repetitions one to four; the fourth says one repetition remains.
    let praise: [String]
    /// Joint groups, any of which shows the body is in view, with their minimum confidence.
    let visibleJoints: [[(BodyJoint, Float)]]
}

/// A cue the Balancing session should speak: an identity, so each is spoken once, its lines and
/// whether the repetition chime leads it.
struct BalanceScriptCue: Equatable {
    let identity: String
    let lines: [NarrationLine]
    var chime = false
}

/// Chooses the 2026-11-23 Balancing scripts' recorded lines from the session's snapshot.
///
/// Like the other scripts it follows any prescription: sentences that state a number play only
/// when true (`ScriptedRepetitions`), and Marizka number clips say other counts.
enum BalanceScriptGuidance {
    /// The script of `exercise` for `arms`, or nil without one. Sit to stand has no side; the arm
    /// scripts are written for the left arm only.
    static func script(for exercise: BalanceExercise, arms: BalanceArmSelection) -> BalanceScript? {
        if exercise == .sitToStand {
            return sitToStand
        }

        guard arms == .left else {
            return nil
        }

        switch exercise {
        case .shoulderFlexion:
            return shoulderFlexion
        case .crossMidline:
            return crossMidline
        case .internalRotation:
            return rotation("internalRotation.left.")
        case .externalRotation:
            return rotation("externalRotation.left.")
        case .sitToStand:
            return sitToStand
        }
    }

    // MARK: - Intro and setup

    static func introduction(_ script: BalanceScript, sets: Int, repetitions: Int) -> [NarrationLine] {
        var keys = script.introduction
        var lines = keys.map { NarrationLine(key: $0) }

        if ScriptedRepetitions.hasRecordedGoals(sets: sets, repetitions: repetitions) {
            lines.append(NarrationLine(key: "scripted.intro.goalsTwoSets %lld", argument: repetitions))
        }

        keys = ["opposition.left.intro.calibration", "scripted.intro.safety"] + script.introNotes + ["scripted.intro.voice"]
        return lines + keys.map { NarrationLine(key: $0) }
    }

    static func bodyVisible(_ frame: TrackingObservation, script: BalanceScript) -> Bool {
        script.visibleJoints.contains { group in
            group.allSatisfy { frame.point($0.0, minimumConfidence: $0.1) != nil }
        }
    }

    // MARK: - Calibration and practice

    /// Calibration lines for a pose step of the engine, before practice.
    static func calibrationCue(for phase: BalanceSnapshot.Phase, script: BalanceScript) -> BalanceScriptCue? {
        switch phase {
        case .calibrating:
            return cue("calibration-start", script.calibrationStart)
        case .calibratingRange:
            return cue("calibration-target", script.calibrationTarget)
        case .returning:
            return cue("calibration-return", script.calibrationReturn)
        default:
            return nil
        }
    }

    /// The arm scripts: a repetition is the way back to the start pose (said with the previous
    /// repetition's praise) and the target.
    static func armCue(phase: BalanceSnapshot.Phase, count: Int, set: Int, goal: Int, script: BalanceScript) -> BalanceScriptCue? {
        switch phase {
        case .reaching:
            let repetition = recorded(count + 1, set: set, goal: goal, script: script)
            let lines = count == 0 ? opening(set) + repetition.start + [repetition.target] : [repetition.target]
            return cue("target-\(set)-\(count + 1)", lines)
        case .returning:
            guard count > 0 else {
                return nil
            }

            var lines = [praise(after: count, goal: goal, script: script)]
            if count < goal {
                lines += recorded(count + 1, set: set, goal: goal, script: script).start.map { NarrationLine(key: $0) }
            }
            return BalanceScriptCue(identity: "back-\(set)-\(count)", lines: lines, chime: true)
        default:
            return nil
        }
    }

    /// Sit to stand: seated, the stand (after the previous repetition's praise); standing, the
    /// way back to the seat. Tracking messages keep their own lines.
    static func sitToStandCue(phase: BalanceSnapshot.Phase, instruction: String, count: Int, set: Int, goal: Int, script: BalanceScript) -> BalanceScriptCue? {
        if instruction == "sts.trackingLost" || instruction == "sts.slowDown" {
            return cue("message-\(instruction)", [instruction])
        }

        let repetition = recorded(count + 1, set: set, goal: goal, script: script)
        // After a stand only: a later set also opens with "sts.sitDown" while still seated.
        if instruction == "sts.sitDown", phase == .holding, let back = repetition.back {
            return cue("back-\(set)-\(count + 1)", [back])
        }

        guard phase == .reaching else {
            return nil
        }

        guard count > 0 else {
            return cue("target-\(set)-1", opening(set) + repetition.start + [repetition.target])
        }

        let lines = [praise(after: count, goal: goal, script: script), NarrationLine(key: repetition.target)]
        return BalanceScriptCue(identity: "target-\(set)-\(count + 1)", lines: lines, chime: true)
    }

    /// "Yuk kita mulai lagi untuk set kedua", recorded for sets two to five.
    private static func opening(_ set: Int) -> [String] {
        set > 1 ? ["scripted.nextSet.\(min(set, 5))"] : []
    }

    private static func cue(_ identity: String, _ keys: [String]) -> BalanceScriptCue? {
        guard !keys.isEmpty else {
            return nil
        }

        return BalanceScriptCue(identity: identity, lines: keys.map { NarrationLine(key: $0) })
    }

    private static func recorded(_ repetition: Int, set: Int, goal: Int, script: BalanceScript) -> BalanceScriptRepetition {
        if set == 1 {
            return script.firstSet[ScriptedRepetitions.recordedRepetition(repetition, goal: goal) - 1]
        }

        return script.laterSets[ScriptedRepetitions.recordedLaterSetRepetition(repetition, goal: goal) - 1]
    }

    /// Recorded praise for the first three repetitions, and for the fourth only when one
    /// repetition remains, as "Tinggal satu repetisi lagi" says. Otherwise the Marizka number.
    private static func praise(after repetition: Int, goal: Int, script: BalanceScript) -> NarrationLine {
        let lastButOne = repetition == 4 && goal == 5
        guard repetition <= 3 || lastButOne else {
            return .number(repetition)
        }

        return NarrationLine(key: script.praise[repetition - 1])
    }

    // MARK: - Scripts

    private static let standardPraise = ["scripted.praise.1", "opposition.left.praise.2", "opposition.left.praise.3", "opposition.left.praise.4"]
    private static let seatedOrStanding = "armRaise.left.prep.posture"
    private static let bodyDetected = "armRaise.left.prep.detected"
    private static let leftCalibrationIntro = "scripted.left.calibration.intro"

    /// Set 1's repetitions one to five from `start` and `target` key suffixes.
    private static func arm(_ p: String, start: String, target: String) -> BalanceScriptRepetition {
        BalanceScriptRepetition(start: [p + start], target: p + target)
    }

    private static let sitToStand: BalanceScript = {
        let p = "sitToStand."
        let first = BalanceScriptRepetition(start: [p + "firstSet.rep.1.start"], target: p + "firstSet.rep.1.target", back: p + "prep.return")
        let second = BalanceScriptRepetition(target: p + "firstSet.rep.2.target", back: p + "firstSet.rep.2.return")
        let third = BalanceScriptRepetition(target: p + "firstSet.rep.3.target", back: p + "firstSet.rep.3.return")

        return BalanceScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            introNotes: [p + "intro.chair", p + "intro.camera"],
            setup: [p + "prep.sit", p + "prep.visible", p + "prep.hands"],
            detected: [bodyDetected, p + "prep.intro"],
            notVisible: p + "prep.visible",
            calibrationStart: [p + "prep.start"],
            calibrationTarget: [p + "prep.target"],
            calibrationReturn: [p + "prep.return"],
            calibrationEnding: ["scripted.calibration.prepared"],
            firstSet: [
                first,
                second,
                third,
                BalanceScriptRepetition(target: p + "firstSet.rep.4.target", back: p + "firstSet.rep.3.return"),
                BalanceScriptRepetition(target: p + "firstSet.rep.5.target", back: p + "firstSet.rep.3.return"),
            ],
            laterSets: [
                BalanceScriptRepetition(start: [p + "laterSet.rep.1.start"], target: p + "firstSet.rep.1.target", back: p + "prep.return"),
                second,
                third,
            ],
            praise: standardPraise,
            // The design follows a shoulder and hip on one side; knees are optional.
            visibleJoints: [
                [(.leftShoulder, 0.3), (.leftHip, 0.3)],
                [(.rightShoulder, 0.3), (.rightHip, 0.3)],
            ]
        )
    }()

    private static let shoulderFlexion: BalanceScript = {
        let p = "shoulderFlexion.left."
        return BalanceScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            setup: [seatedOrStanding, p + "prep.upright", "scripted.body.armsDown"],
            detected: [bodyDetected, leftCalibrationIntro],
            notVisible: p + "prep.notVisible",
            calibrationStart: [p + "prep.start"],
            calibrationTarget: [p + "prep.target"],
            calibrationEnding: [p + "prep.return", "scripted.calibration.prepared"],
            firstSet: [
                arm(p, start: "firstSet.rep.1.start", target: "firstSet.rep.1.target"),
                arm(p, start: "firstSet.rep.2.start", target: "firstSet.rep.2.target"),
                arm(p, start: "firstSet.rep.3.start", target: "firstSet.rep.3.target"),
                arm(p, start: "firstSet.rep.4.start", target: "firstSet.rep.4.target"),
                arm(p, start: "firstSet.rep.5.start", target: "firstSet.rep.4.target"),
            ],
            laterSets: [
                arm(p, start: "laterSet.rep.1.start", target: "firstSet.rep.1.target"),
                arm(p, start: "firstSet.rep.2.start", target: "firstSet.rep.2.target"),
                arm(p, start: "laterSet.rep.3.start", target: "firstSet.rep.3.target"),
            ],
            praise: standardPraise,
            visibleJoints: [[(.leftShoulder, 0.3), (.rightShoulder, 0.3), (.leftElbow, 0.2), (.leftWrist, 0.2)]]
        )
    }()

    /// Cross midline captures no end pose, so its calibration says only the start pose.
    private static let crossMidline: BalanceScript = {
        let p = "crossMidline.left."
        return BalanceScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            setup: [seatedOrStanding, p + "prep.upright", "scripted.body.armsDown"],
            detected: [bodyDetected, leftCalibrationIntro],
            notVisible: "armRaise.left.prep.notVisible",
            calibrationStart: [p + "prep.start"],
            calibrationTarget: [],
            calibrationEnding: ["scripted.calibration.prepared"],
            firstSet: [
                arm(p, start: "firstSet.rep.1.start", target: "firstSet.rep.1.target"),
                arm(p, start: "firstSet.rep.2.start", target: "firstSet.rep.2.target"),
                arm(p, start: "firstSet.rep.3.start", target: "firstSet.rep.3.target"),
                arm(p, start: "firstSet.rep.4.start", target: "firstSet.rep.4.target"),
                arm(p, start: "firstSet.rep.5.start", target: "firstSet.rep.3.target"),
            ],
            laterSets: [
                arm(p, start: "laterSet.rep.1.start", target: "firstSet.rep.1.target"),
                arm(p, start: "firstSet.rep.2.start", target: "firstSet.rep.2.target"),
                arm(p, start: "firstSet.rep.5.start", target: "firstSet.rep.3.target"),
            ],
            praise: standardPraise,
            visibleJoints: [[(.leftShoulder, 0.3), (.rightShoulder, 0.3), (.leftWrist, 0.2), (.leftHip, 0.3)]]
        )
    }()

    /// Internal and external rotation share every line but the turn ("dalam" or "luar").
    private static func rotation(_ k: String) -> BalanceScript {
        let q = "shoulderRotation.left."

        func turn(_ start: String, _ target: Int) -> BalanceScriptRepetition {
            BalanceScriptRepetition(start: [q + start], target: k + "firstSet.rep.\(target).target")
        }

        return BalanceScript(
            introduction: [k + "intro.title", k + "intro.purpose"],
            setup: [seatedOrStanding, q + "prep.upright", "scripted.body.armsDown"],
            detected: [bodyDetected, leftCalibrationIntro, q + "prep.otherArm"],
            notVisible: q + "prep.notVisible",
            calibrationStart: [q + "prep.start"],
            calibrationTarget: [k + "prep.target"],
            calibrationEnding: [q + "prep.return", "scripted.calibration.prepared"],
            firstSet: [
                turn("firstSet.rep.1.start", 1),
                turn("firstSet.rep.2.start", 2),
                turn("firstSet.rep.3.start", 3),
                turn("firstSet.rep.4.start", 4),
                turn("firstSet.rep.5.start", 3),
            ],
            laterSets: [
                turn("laterSet.rep.1.start", 1),
                turn("firstSet.rep.2.start", 2),
                turn("firstSet.rep.3.start", 3),
            ],
            praise: standardPraise,
            visibleJoints: [[(.leftShoulder, 0.3), (.rightShoulder, 0.3), (.leftElbow, 0.2)]]
        )
    }
}
