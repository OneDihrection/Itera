//
//  LeftArmRaiseGuidance.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 14/11/2026.
//

import Foundation

/// The approved left-arm script never substitutes its fixed totals for another prescription.
enum LeftArmRaiseGuidance {
    static let prefix = "armRaise.left."
    static let introduction = ["armRaise.left.intro.focus", "armRaise.left.intro.goals"]

    static func applies(to activity: SessionActivity) -> Bool {
        activity.kind == .armRaise
            && activity.side == .left
            && activity.sets == 2
            && activity.goal == 5
    }

    static func movementKey(_ movement: MovementSnapshot, set: Int) -> String {
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
            let repetition = min(5, movement.count + 1)
            let action = movement.guide?.targetActive == true ? "raise" : "return"
            return prefix + "rep.\(repetition).\(action)"
        }
    }
}

/// A short rest with three breaths. Every phase waits for its own narration and minimum time,
/// so a slow Marizka recording cannot be cut off by the next cue. Pauses earn no elapsed time.
struct GuidedSetBreathing {
    private(set) var step = 0
    private(set) var elapsed = 0.0
    private var lastTick: Double?
    private var narrationFinished = false

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
