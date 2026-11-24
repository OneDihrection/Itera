//
//  GuidedScriptGuidance.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 24/11/2026.
//

import Foundation

/// The Indonesian scripts the guided session (`SessionEngine`) speaks: arm raise (both arms,
/// through `ArmRaiseGuidance`), and, on the left arm, elbow bend and directional reach (scripts of
/// 2026-11-24, see Documentation/LeftScriptsNarration.md).
///
/// Every function answers for one exercise kind and side, so the engine never names an exercise.
/// Recordings that state a number play only when it is true (`ScriptedRepetitions`); Marizka
/// number clips say other counts.
enum GuidedScriptGuidance {
    /// Whether a script narrates `activity`. Arm raise keeps its rules; elbow bend and directional
    /// reach are written for the left arm practised on its own.
    static func applies(to activity: SessionActivity) -> Bool {
        switch activity.kind {
        case .armRaise:
            return ArmRaiseGuidance.applies(to: activity)
        case .elbowBend, .directionalReach:
            return activity.side == .left && !activity.alternatesSides
        default:
            return false
        }
    }

    /// The 2026-11-23/24 scripts: every one but the right arm raise's approved 14/11 brief.
    static func isRevised(_ kind: TherapyKind, side: TherapySide) -> Bool {
        kind != .armRaise || ArmRaiseGuidance.usesRevisedScript(side)
    }

    // MARK: - Intro and opening

    static func introduction(_ kind: TherapyKind, side: TherapySide, sets: Int, repetitions: Int) -> [NarrationLine] {
        let notes: (title: [String], calibration: String)
        switch kind {
        case .elbowBend:
            notes = (["elbowBend.left.intro.title", "elbowBend.left.intro.purpose"], "opposition.left.intro.calibration")
        case .directionalReach:
            notes = (["directionalReach.left.intro.title", "directionalReach.left.intro.purpose"], "directionalReach.left.intro.calibration")
        default:
            return ArmRaiseGuidance.introduction(for: side, sets: sets, repetitions: repetitions)
        }

        var lines = notes.title.map { NarrationLine(key: $0) }
        if ScriptedRepetitions.hasRecordedGoals(sets: sets, repetitions: repetitions) {
            lines.append(NarrationLine(key: "scripted.intro.goalsTwoSets %lld", argument: repetitions))
        }
        return lines + [notes.calibration, "scripted.intro.safety", "scripted.intro.voice"].map { NarrationLine(key: $0) }
    }

    /// Phase 1: posture and what the camera must see.
    static func setupLines(_ kind: TherapyKind, side: TherapySide) -> [NarrationLine] {
        switch kind {
        case .elbowBend:
            return keys([posture, "elbowBend.left.prep.turn", "elbowBend.left.prep.visible", "scripted.body.armsDown"])
        case .directionalReach:
            return keys([posture, "directionalReach.left.prep.visible", "scripted.body.armsDown"])
        default:
            return ArmRaiseGuidance.setupLines(for: side)
        }
    }

    /// Phase 2's opening once the body is in view, ending with the start pose.
    static func calibrationStartLines(_ kind: TherapyKind, side: TherapySide) -> [NarrationLine] {
        switch kind {
        case .elbowBend:
            return keys([bodyDetected, "scripted.left.calibration.intro", "elbowBend.left.prep.start"])
        case .directionalReach:
            return keys([
                bodyDetected,
                "scripted.left.calibration.intro",
                "directionalReach.left.prep.directions",
                "directionalReach.left.prep.start",
            ])
        default:
            return ArmRaiseGuidance.calibrationStartLines(for: side)
        }
    }

    static func bodyNotVisibleKey(_ kind: TherapyKind, side: TherapySide) -> String {
        switch kind {
        case .elbowBend:
            return "elbowBend.left.prep.visible"
        case .directionalReach:
            return "directionalReach.left.prep.visible"
        default:
            return ArmRaiseGuidance.bodyNotVisibleKey(for: side)
        }
    }

    /// Joints that show the body is in view, with their minimum confidence, as the activity reads them.
    static func visibleJoints(_ kind: TherapyKind, side: TherapySide) -> [(BodyJoint, Float)] {
        let left = side == .left
        let elbow: BodyJoint = left ? .leftElbow : .rightElbow
        let wrist: BodyJoint = left ? .leftWrist : .rightWrist
        let hip: BodyJoint = left ? .leftHip : .rightHip
        let shoulders: [(BodyJoint, Float)] = [(.leftShoulder, 0.3), (.rightShoulder, 0.3)]

        switch kind {
        case .elbowBend:
            return shoulders + [(elbow, 0.2), (wrist, 0.2)]
        case .directionalReach:
            return shoulders + [(elbow, 0.2), (wrist, 0.2)]
        default:
            return shoulders + [(hip, 0.3), (elbow, 0.2)]
        }
    }

    static func calibrationCompleteKey(_ kind: TherapyKind, side: TherapySide) -> String {
        kind == .armRaise ? ArmRaiseGuidance.calibrationCompleteKey(for: side) : "scripted.left.calibration.prepared"
    }

    /// The countdown cue before practice; later sets say "Set selanjutnya akan dimulai dalam".
    static func countdownKey(_ kind: TherapyKind, side: TherapySide, set: Int) -> String {
        guard kind != .armRaise else {
            return ArmRaiseGuidance.prefix(for: side) + (set == 1 ? "countdown.first" : "countdown.next")
        }

        return set == 1 ? "calibration.countdown" : "scripted.countdown.next"
    }

    // MARK: - Practice

    /// The movement cue of a `MovementActivity` script (arm raise, elbow bend).
    static func movementKey(_ kind: TherapyKind, movement: MovementSnapshot, set: Int, goal: Int, side: TherapySide) -> String {
        guard kind == .elbowBend else {
            return ArmRaiseGuidance.movementKey(movement, set: set, goal: goal, side: side)
        }

        let p = "elbowBend.left."
        switch movement.phase {
        case .startCapture:
            return p + "prep.start"
        case .targetCapture:
            return p + "prep.target"
        case .returnToStart:
            return p + "prep.return"
        case .countdown:
            return countdownKey(kind, side: side, set: set)
        case .practice:
            let repetition = elbowRepetition(movement.count + 1, set: set, goal: goal)
            return movement.instruction == "session.moveTarget" ? repetition.target : repetition.back
        }
    }

    /// Lines spoken before a later set's first target: "Yuk kita mulai lagi untuk set kedua".
    /// Arm raise repeats its first repetition's opening instead.
    static func laterSetOpening(_ kind: TherapyKind, movement: MovementSnapshot, set: Int) -> [String] {
        guard kind != .armRaise,
              set > 1,
              movement.phase == .practice,
              movement.count == 0,
              movement.instruction == "session.moveTarget" else {
            return []
        }

        return [nextSetKey(set)]
    }

    /// Recorded praise after `repetition`, or nil when no recording says it truthfully; the
    /// session then speaks the Marizka number.
    static func praiseKey(_ kind: TherapyKind, after repetition: Int, goal: Int, side: TherapySide) -> String? {
        guard kind != .armRaise else {
            return ArmRaiseGuidance.praiseKey(after: repetition, side: side)
        }

        let lastButOne = repetition == 4 && goal == 5
        guard (1...3).contains(repetition) || lastButOne else {
            return nil
        }

        return praise[repetition - 1]
    }

    /// Prefix of the short rest's `BreathingRest` keys.
    static func restPrefix(_ kind: TherapyKind, side: TherapySide) -> String {
        kind == .armRaise ? ArmRaiseGuidance.restPrefix(for: side) : "scripted."
    }

    static func breathingRest(_ kind: TherapyKind, afterSet finishedSet: Int, side: TherapySide, minimumSeconds: Double) -> BreathingRest {
        guard kind == .armRaise else {
            return BreathingRest(openingAfterSet: finishedSet, minimumSeconds: minimumSeconds)
        }

        return ArmRaiseGuidance.breathingRest(afterSet: finishedSet, side: side, minimumSeconds: minimumSeconds)
    }

    // MARK: - Directional reach

    /// A directional-reach cue: an identity so each moment is spoken once, its lines, and whether
    /// the repetition chime leads it (after a credited round).
    struct ReachCue: Equatable {
        let identity: String
        let lines: [NarrationLine]
        var chime = false
    }

    /// The script's line for the current reach moment: each direction of the calibration with its
    /// return, then every round's three directions and returns. The uncounted rehearsal round
    /// after calibration speaks the first round's lines.
    static func reachCue(_ reach: ReachSnapshot, set: Int, goal: Int) -> ReachCue? {
        let p = "directionalReach.left."
        let direction = min(max(reach.direction, 0), 2)
        let returning = reach.instruction == "session.returnStart"

        switch reach.phase {
        case .assessment:
            let outward = [p + "prep.cross", p + "prep.side", p + "prep.up"]
            let back = [p + "prep.crossReturn", p + "prep.sideReturn", p + "prep.upReturn"]
            let key = returning ? back[direction] : outward[direction]
            return ReachCue(identity: "assess-\(direction)-\(returning)", lines: [NarrationLine(key: key)])
        case .rehearsal, .practice:
            let completed = reach.phase == .rehearsal ? 0 : reach.count
            let round = reachRound(completed + 1, set: set, goal: goal)
            let identity = "\(set)-\(reach.phase)-\(completed)-\(direction)-\(returning)"

            if returning {
                return ReachCue(identity: identity, lines: [NarrationLine(key: round.returns[direction])])
            }

            guard direction == 0 else {
                return ReachCue(identity: identity, lines: [NarrationLine(key: round.outward[direction])])
            }

            // A round's first direction opens it: the rehearsal, a later set's first round, or the
            // previous round's praise.
            if reach.phase == .rehearsal || (completed == 0 && set > 1) {
                let opening = set > 1 ? [nextSetKey(set)] : []
                return ReachCue(identity: identity, lines: keys(opening + round.start + [round.outward[0]]))
            }

            guard completed > 0 else {
                return ReachCue(identity: identity, lines: [NarrationLine(key: round.outward[0])])
            }

            let praiseLine = praiseKey(.directionalReach, after: completed, goal: goal, side: .left)
                .map { NarrationLine(key: $0) } ?? .number(completed)
            return ReachCue(identity: identity, lines: [praiseLine, NarrationLine(key: round.outward[0])], chime: true)
        default:
            return nil
        }
    }

    // MARK: - Tables

    private static let posture = "armRaise.left.prep.posture"
    private static let bodyDetected = "armRaise.left.prep.detected"
    private static let praise = ["scripted.praise.1", "opposition.left.praise.2", "opposition.left.praise.3", "opposition.left.praise.4"]

    private static func keys(_ keys: [String]) -> [NarrationLine] {
        keys.map { NarrationLine(key: $0) }
    }

    private static func nextSetKey(_ set: Int) -> String {
        "scripted.nextSet.\(min(max(set, 2), 5))"
    }

    private struct ElbowRepetition {
        let target: String
        let back: String
    }

    private static func elbowRepetition(_ repetition: Int, set: Int, goal: Int) -> ElbowRepetition {
        let p = "elbowBend.left."

        func rep(_ target: String, _ back: String) -> ElbowRepetition {
            ElbowRepetition(target: p + target, back: p + back)
        }

        let first = [
            rep("firstSet.rep.1.target", "firstSet.rep.1.return"),
            rep("firstSet.rep.2.target", "firstSet.rep.2.return"),
            rep("firstSet.rep.3.target", "firstSet.rep.3.return"),
            rep("firstSet.rep.4.target", "firstSet.rep.2.return"),
            rep("firstSet.rep.3.target", "firstSet.rep.3.return"),
        ]
        guard set == 1 else {
            let later = [rep("laterSet.rep.1.target", "firstSet.rep.1.return"), first[1], first[2]]
            return later[ScriptedRepetitions.recordedLaterSetRepetition(repetition, goal: goal) - 1]
        }

        return first[ScriptedRepetitions.recordedRepetition(repetition, goal: goal) - 1]
    }

    private struct ReachRound {
        var start: [String] = []
        /// Across, to the side, up.
        let outward: [String]
        /// The return after each direction.
        let returns: [String]
    }

    private static func reachRound(_ repetition: Int, set: Int, goal: Int) -> ReachRound {
        let p = "directionalReach.left."
        let back = Array(repeating: p + "return.back", count: 3)
        let short = Array(repeating: p + "return.short", count: 3)

        func moves(_ cross: String, _ side: String, _ up: String) -> [String] {
            [p + cross, p + side, p + up]
        }

        let third = ReachRound(outward: moves("firstSet.rep.3.cross", "firstSet.rep.3.side", "firstSet.rep.3.up"), returns: short)
        let first = [
            ReachRound(
                start: [p + "firstSet.rep.1.start"],
                outward: moves("firstSet.rep.1.cross", "firstSet.rep.1.side", "prep.up"),
                returns: [p + "prep.crossReturn", p + "return.back", p + "return.back"]
            ),
            ReachRound(outward: moves("firstSet.rep.2.cross", "firstSet.rep.2.side", "firstSet.rep.2.up"), returns: back),
            third,
            ReachRound(outward: moves("firstSet.rep.4.cross", "firstSet.rep.4.side", "firstSet.rep.4.up"), returns: short),
            ReachRound(outward: moves("firstSet.rep.5.cross", "firstSet.rep.4.side", "firstSet.rep.4.up"), returns: back),
        ]
        guard set == 1 else {
            let later = [
                ReachRound(
                    start: [p + "laterSet.rep.1.start"],
                    outward: moves("laterSet.rep.1.cross", "firstSet.rep.2.side", "firstSet.rep.2.up"),
                    returns: back
                ),
                third,
                third,
            ]
            return later[ScriptedRepetitions.recordedLaterSetRepetition(repetition, goal: goal) - 1]
        }

        return first[ScriptedRepetitions.recordedRepetition(repetition, goal: goal) - 1]
    }
}
