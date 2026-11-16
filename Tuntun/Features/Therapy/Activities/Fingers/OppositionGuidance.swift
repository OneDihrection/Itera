//
//  OppositionGuidance.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 14/11/2026.
//

import Foundation

/// The approved thumb-opposition scripts share movement rules, while every cue keeps its trained
/// side in the recording key. They follow any prescription: recordings that name a number play
/// only when it is true (see `ScriptedRepetitions`), and Marizka number clips carry other counts.
enum OppositionGuidance {
    static func prefix(for side: HandSide) -> String {
        "opposition." + side.rawValue + "."
    }

    static func applies(to kind: FingerExercise) -> Bool {
        kind == .opposition
    }

    /// The intro names its goals ("dua set… lima repetisi") only for the recorded prescription;
    /// otherwise the screen shows them.
    static func introductionKeys(for side: HandSide, routine: FingerRoutine) -> [String] {
        var keys = ["intro.title", "intro.focus"]
        if ScriptedRepetitions.matchesRecording(sets: routine.sets, repetitions: routine.repetitions) {
            keys.append("intro.goals")
        }
        if side == .left {
            keys.append("intro.voice")
        }
        return keys.map { prefix(for: side) + $0 }
    }

    /// The recorded lines for the current moment, in speaking order, with full catalog keys.
    /// A count no recording states truthfully is a Marizka number line.
    static func movementLines(for activity: FingerActivity, side: HandSide) -> [NarrationLine] {
        let prefix = prefix(for: side)
        let finger = activity.finger
        let goal = activity.routine.repetitions

        func line(_ key: String) -> NarrationLine {
            NarrationLine(key: prefix + key)
        }

        switch activity.phase {
        case .baseline:
            return [line(finger == 0 ? "calibration.start" : "calibration.open")]
        case .target:
            return [line("calibration.touch.\(finger)")]
        case .demonstration:
            return [line("calibration.complete")]
        case .countdown:
            return [line(activity.set == 1 ? "countdown.first" : "countdown.next")]
        case .active:
            let repetition = activity.repetitions + 1
            let recorded = ScriptedRepetitions.recordedRepetition(repetition, goal: goal)
            let root = "rep.\(recorded)."

            if activity.needsStart {
                // Pause invalidates an unfinished cycle. Re-open, then repeat the current
                // finger; do not announce the next repetition or praise discarded movement.
                return repetition == 1 && finger == 0
                    ? [line(root + "opening")]
                    : [line("calibration.open")]
            }

            if activity.returning {
                return [line(root + "open.\(finger)")]
            }

            var lines: [NarrationLine] = []
            if finger == 0, repetition > 1 {
                lines.append(praise(after: repetition - 1, goal: goal, prefix: prefix))
                if repetition < goal {
                    lines.append(line(openingKey(for: repetition, recorded: recorded)))
                }
            }
            lines.append(line(root + "touch.\(finger)"))
            return lines
        case .feedback:
            return summaryLines(completedSets: activity.completedSets, routine: activity.routine, prefix: prefix)
        default:
            return []
        }
    }

    /// "rep.3.opening" names the third repetition; other openings carry no number.
    private static func openingKey(for repetition: Int, recorded: Int) -> String {
        if recorded == 3, repetition != 3 {
            return "rep.4.opening"
        }

        return "rep.\(recorded).opening"
    }

    /// Recorded praise for the first three repetitions, and for the fourth only when one
    /// repetition remains, as its "satu repetisi lagi" says. Otherwise the Marizka number.
    private static func praise(after repetition: Int, goal: Int, prefix: String) -> NarrationLine {
        let lastButOne = repetition == 4 && goal == ScriptedRepetitions.recordedRepetitions
        guard repetition <= 3 || lastButOne else {
            return .number(repetition)
        }

        return NarrationLine(key: prefix + "rep.\(repetition).complete")
    }

    /// The recorded set summary when its numbers are true ("summary.first": five repetitions
    /// and a second set to come; "summary.final": ten in two sets). Otherwise the set's
    /// repetitions as a Marizka number, then the general set or exercise ending.
    private static func summaryLines(completedSets: Int, routine: FingerRoutine, prefix: String) -> [NarrationLine] {
        let goal = routine.repetitions
        let finalSet = completedSets >= routine.sets

        if goal == ScriptedRepetitions.recordedRepetitions {
            if completedSets == 1, routine.sets >= 2 {
                return [NarrationLine(key: prefix + "summary.first")]
            }
            if finalSet, routine.sets == ScriptedRepetitions.recordedSets {
                return [NarrationLine(key: prefix + "summary.final")]
            }
        }

        return [.number(goal), NarrationLine(key: finalSet ? "session.feedback" : "session.good")]
    }
}

/// A three-breath break whose phases wait for both the spoken cue and their minimum duration.
/// No wall-clock timeout may cut off a long, gently spoken inhale instruction.
struct OppositionRest {
    private(set) var step: Int
    private(set) var elapsed = 0.0
    private var lastTick: Double?
    private(set) var narrationFinished = false

    var finished: Bool { step > 10 }

    /// "rest.opening" says set one is done and set two follows, so later rests start with the
    /// first breath.
    init(opensAfterFirstSet: Bool) {
        step = opensAfterFirstSet ? 0 : 1
    }

    var key: String {
        if step == 0 {
            return "rest.opening"
        }
        if step >= 10 {
            return "rest.closing"
        }
        let breath = (step - 1) / 3 + 1
        switch (step - 1) % 3 {
        case 0: return "rest.inhale.\(breath)"
        case 1: return breath == 1 ? "rest.hold.first" : "rest.hold"
        default: return breath == 3 ? "rest.exhale.last" : "rest.exhale"
        }
    }

    private var duration: Double {
        guard step > 0, step < 10 else {
            return 0
        }
        switch (step - 1) % 3 {
        case 0: return 6
        case 1: return 2
        default: return 3
        }
    }

    var intensity: Double {
        guard step > 0, step < 10 else {
            return 0.25
        }
        let fraction = min(1, elapsed / duration)
        let expansion: Double
        switch (step - 1) % 3 {
        case 0: expansion = fraction
        case 1: expansion = 1
        default: expansion = 1 - fraction
        }
        return 0.25 + 0.75 * (1 - cos(expansion * .pi)) / 2
    }

    mutating func guidanceCompleted() {
        narrationFinished = true
    }

    mutating func suspend() {
        lastTick = nil
        narrationFinished = false
    }

    mutating func tick(_ now: Double, ready: Bool) {
        guard ready, !finished else {
            lastTick = nil
            return
        }
        elapsed += min(0.2, max(0, now - (lastTick ?? now)))
        lastTick = now
        guard elapsed >= duration, narrationFinished else {
            return
        }
        step += 1
        elapsed = 0
        narrationFinished = false
    }
}
