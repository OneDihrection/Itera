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

    /// The intro names its goals ("dua set… lima repetisi") only for the recorded prescription;
    /// otherwise the screen shows them.
    static func introduction(for side: TherapySide, sets: Int, repetitions: Int) -> [String] {
        let prefix = prefix(for: side)
        guard ScriptedRepetitions.matchesRecording(sets: sets, repetitions: repetitions) else {
            return [prefix + "intro.focus"]
        }

        return [prefix + "intro.focus", prefix + "intro.goals"]
    }

    static func applies(to activity: SessionActivity) -> Bool {
        activity.kind == .armRaise
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

    static func movementKey(_ movement: MovementSnapshot, set: Int, goal: Int, side: TherapySide) -> String {
        let prefix = prefix(for: side)
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
}

/// A short rest with three breaths. Every phase waits for its own narration and minimum time,
/// so a slow Marizka recording cannot be cut off by the next cue. Pauses earn no elapsed time.
struct GuidedSetBreathing {
    private(set) var step: Int
    private(set) var elapsed = 0.0
    private var lastTick: Double?
    private var narrationFinished = false

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

    mutating func tick(_ now: Double) {
        guard !finished else {
            return
        }
        elapsed += min(0.2, max(0, now - (lastTick ?? now)))
        lastTick = now
        guard narrationFinished, elapsed >= duration else {
            return
        }
        step += 1
        elapsed = 0
        narrationFinished = false
    }
}
