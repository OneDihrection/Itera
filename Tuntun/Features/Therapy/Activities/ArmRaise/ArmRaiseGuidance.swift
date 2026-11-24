//
//  ArmRaiseGuidance.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 14/11/2026.
//

import Foundation

/// The approved arm-raise scripts share progression while keeping anatomical side in every
/// recording key. They follow any prescription: recordings that name a number play only when
/// it is true (see `ScriptedRepetitions`), and the session speaks other counts with Marizka
/// number clips.
enum ArmRaiseGuidance {
    static func prefix(for side: TherapySide) -> String {
        "armRaise." + side.rawValue + "."
    }

    /// The left arm follows the revised script of 2026-11-23; the right arm keeps the approved
    /// 14/11 script.
    static func usesRevisedScript(_ side: TherapySide) -> Bool {
        side == .left
    }

    /// The intro names its goals only when a recording states them truthfully; otherwise the
    /// screen shows them.
    static func introduction(for side: TherapySide, sets: Int, repetitions: Int) -> [NarrationLine] {
        let prefix = prefix(for: side)
        guard usesRevisedScript(side) else {
            guard ScriptedRepetitions.matchesRecording(sets: sets, repetitions: repetitions) else {
                return [NarrationLine(key: prefix + "intro.focus")]
            }
            return [NarrationLine(key: prefix + "intro.focus"), NarrationLine(key: prefix + "intro.goals")]
        }

        var lines = [prefix + "intro.title", prefix + "intro.purpose"].map { NarrationLine(key: $0) }
        if ScriptedRepetitions.hasRecordedGoals(sets: sets, repetitions: repetitions) {
            lines.append(NarrationLine(key: "scripted.intro.goalsTwoSets %lld", argument: repetitions))
        }
        lines += [prefix + "intro.calibration", "scripted.intro.safety", "scripted.intro.voice"]
            .map { NarrationLine(key: $0) }
        return lines
    }

    // MARK: - Setup and calibration

    /// Phase 1: how to sit or stand and what the camera must see.
    static func setupLines(for side: TherapySide) -> [NarrationLine] {
        let prefix = prefix(for: side)
        guard usesRevisedScript(side) else {
            return [NarrationLine(key: prefix + "calibration.position")]
        }

        return [prefix + "prep.posture", prefix + "prep.upright", prefix + "prep.armsDown"]
            .map { NarrationLine(key: $0) }
    }

    /// Phase 2, once the body is in view: the revised script confirms it, then starts calibrating.
    static func calibrationStartLines(for side: TherapySide) -> [NarrationLine] {
        let prefix = prefix(for: side)
        guard usesRevisedScript(side) else {
            return [NarrationLine(key: prefix + "calibration.start")]
        }

        return [prefix + "prep.detected", "scripted.left.calibration.intro", prefix + "prep.start"]
            .map { NarrationLine(key: $0) }
    }

    /// Said while the revised script waits for the shoulders, hips and arms to come into view.
    static func bodyNotVisibleKey(for side: TherapySide) -> String {
        prefix(for: side) + "prep.notVisible"
    }

    static func calibrationCompleteKey(for side: TherapySide) -> String {
        usesRevisedScript(side) ? "scripted.left.calibration.prepared" : prefix(for: side) + "calibration.complete"
    }

    /// Prefix of the short rest's `BreathingRest` keys.
    static func restPrefix(for side: TherapySide) -> String {
        usesRevisedScript(side) ? "scripted." : prefix(for: side)
    }

    /// The short rest after `finishedSet`: the revised script names every set it closes.
    static func breathingRest(afterSet finishedSet: Int, side: TherapySide, minimumSeconds: Double) -> BreathingRest {
        guard usesRevisedScript(side) else {
            return BreathingRest(opensAfterFirstSet: finishedSet == 1, minimumSeconds: minimumSeconds)
        }

        return BreathingRest(openingAfterSet: finishedSet, minimumSeconds: minimumSeconds)
    }

    /// The briefs name one arm, so an arm raise whose sides take turns keeps the general guidance.
    static func applies(to activity: SessionActivity) -> Bool {
        activity.kind == .armRaise && !activity.alternatesSides
    }

    /// Praise after `repetition`, or nil when no recording says it ("Satu repetisi selesai"
    /// exists for the first four); the session then speaks the Marizka number instead.
    static func praiseKey(after repetition: Int, side: TherapySide) -> String? {
        guard (1...4).contains(repetition) else {
            return nil
        }

        return prefix(for: side) + "rep.\(repetition).complete"
    }

    /// The recorded set summary when its numbers are true, otherwise nil. "summary.first"
    /// promises five repetitions and a second set; "summary.final" ten repetitions in two sets.
    static func summaryKey(setNumber: Int, sets: Int, goal: Int, side: TherapySide) -> String? {
        if usesRevisedScript(side) {
            return revisedSummary(setNumber: setNumber, sets: sets, goal: goal)?.screen
        }

        guard goal == ScriptedRepetitions.recordedRepetitions else {
            return nil
        }

        if setNumber == 1, sets >= 2 {
            return prefix(for: side) + "summary.first"
        }

        if setNumber == sets, sets == ScriptedRepetitions.recordedSets {
            return prefix(for: side) + "summary.final"
        }

        return nil
    }

    /// The revised script's set summary: the screen shows the count-free sentence (its totals
    /// tile has the numbers), Marizka says the total when recorded and what follows. Nil for a
    /// set between the first and the last, which keeps the general ending.
    static func revisedSummary(setNumber: Int, sets: Int, goal: Int) -> (screen: String, spoken: [NarrationLine])? {
        if setNumber >= sets {
            let total = goal * sets
            let summary = ScriptedRepetitions.recordedTotals.contains(total)
                ? NarrationLine(key: "scripted.summary.finalTotal %lld", argument: total)
                : NarrationLine(key: "scripted.summary.final")
            return ("scripted.summary.final", [summary, NarrationLine(key: "scripted.summary.thanks")])
        }

        if setNumber == 1 {
            let summary = ScriptedRepetitions.recordedGoals.contains(goal)
                ? NarrationLine(key: "scripted.summary.firstTotal %lld", argument: goal)
                : NarrationLine(key: "scripted.summary.first")
            return ("scripted.summary.first", [summary, NarrationLine(key: "scripted.summary.restBeforeSecondSet")])
        }

        return nil
    }

    static func movementKey(_ movement: MovementSnapshot, set: Int, goal: Int, side: TherapySide) -> String {
        let prefix = prefix(for: side)
        if usesRevisedScript(side) {
            return revisedMovementKey(movement, set: set, goal: goal, prefix: prefix)
        }

        switch movement.phase {
        case .startCapture:
            return prefix + "calibration.start"
        case .targetCapture:
            return prefix + "calibration.target"
        case .returnToStart:
            return prefix + "calibration.return"
        case .countdown:
            return prefix + (set == 1 ? "countdown.first" : "countdown.next")
        case .practice:
            let repetition = ScriptedRepetitions.recordedRepetition(movement.count + 1, goal: goal)
            let action = movement.instruction == "session.moveTarget" ? "raise" : "return"
            return prefix + "rep.\(repetition).\(action)"
        }
    }

    /// The revised left script: its own calibration lines, and in the first set its own wording
    /// for repetitions four and five; everything else is the approved recording.
    private static func revisedMovementKey(_ movement: MovementSnapshot, set: Int, goal: Int, prefix: String) -> String {
        switch movement.phase {
        case .startCapture:
            return prefix + "prep.start"
        case .targetCapture:
            return prefix + "prep.target"
        case .returnToStart:
            return prefix + "prep.return"
        case .countdown:
            return prefix + (set == 1 ? "countdown.first" : "countdown.next")
        case .practice:
            let repetition = ScriptedRepetitions.recordedRepetition(movement.count + 1, goal: goal)
            let action = movement.instruction == "session.moveTarget" ? "raise" : "return"
            let firstSetVariant = set == 1 && repetition >= 4
            return prefix + (firstSetVariant ? "firstSet." : "") + "rep.\(repetition).\(action)"
        }
    }
}
