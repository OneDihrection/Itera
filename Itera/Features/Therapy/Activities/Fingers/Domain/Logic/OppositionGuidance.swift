//
//  OppositionGuidance.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 14/11/2026.
//

import Foundation

/// The approved two-set, five-repetition scripts share movement rules, while every cue keeps
/// its trained side in the recording key. Other prescriptions retain their existing guidance.
enum OppositionGuidance {
    static func prefix(for side: HandSide) -> String {
        "opposition." + side.rawValue + "."
    }

    static func applies(to kind: FingerExercise, routine: FingerRoutine) -> Bool {
        kind == .opposition
            && routine.sets == 2
            && routine.repetitions == 5
    }

    static func introductionKeys(for side: HandSide) -> [String] {
        var keys = ["intro.title", "intro.focus", "intro.goals"]
        if side == .left {
            keys.append("intro.voice")
        }
        return keys.map { prefix(for: side) + $0 }
    }

    static func movementKeys(for activity: FingerActivity) -> [String] {
        let finger = activity.finger

        switch activity.phase {
        case .baseline:
            return [finger == 0 ? "calibration.start" : "calibration.open"]
        case .target:
            return ["calibration.touch.\(finger)"]
        case .demonstration:
            return ["calibration.complete"]
        case .countdown:
            return [activity.set == 1 ? "countdown.first" : "countdown.next"]
        case .active:
            let repetition = activity.repetitions + 1
            let root = "rep.\(repetition)."

            if activity.needsStart {
                // Pause invalidates an unfinished cycle. Re-open, then repeat the current
                // finger; do not announce the next repetition or praise discarded movement.
                return repetition == 1 && finger == 0
                    ? [root + "opening"]
                    : ["calibration.open"]
            }

            if activity.returning {
                return [root + "open.\(finger)"]
            }

            var keys: [String] = []
            if finger == 0, repetition > 1 {
                keys.append("rep.\(repetition - 1).complete")
                if repetition < 5 {
                    keys.append(root + "opening")
                }
            }
            keys.append(root + "touch.\(finger)")
            return keys
        case .feedback:
            return [activity.completedSets == 1 ? "summary.first" : "summary.final"]
        default:
            return []
        }
    }
}

/// A three-breath break whose phases wait for both the spoken cue and their minimum duration.
/// No wall-clock timeout may cut off a long, gently spoken inhale instruction.
struct OppositionRest {
    private(set) var step = 0
    private(set) var elapsed = 0.0
    private var lastTick: Double?
    private(set) var narrationFinished = false

    var finished: Bool { step > 10 }
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
