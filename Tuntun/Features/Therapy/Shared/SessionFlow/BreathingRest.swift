//
//  BreathingRest.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation

/// The scripted short rest between sets: an optional opening, three breaths of inhale, hold and
/// exhale, and a closing. Every step waits for its own narration and its minimum time, so a slow
/// Marizka recording is never cut off by the next cue. Pauses and unready time earn no elapsed time.
///
/// Used by the Indonesian arm-raise script (`SessionEngine`) and thumb-opposition script
/// (`FingerSessionViewModel`). The timed rest keeps its stateless rhythm, `RestBreath`.
struct BreathingRest {
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

    /// Minimum seconds of the current step: inhale 6, hold 2, exhale 3; opening and closing 0.
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

    /// Credits at most 0.2 s per tick. While `ready` is false nothing is credited and the next
    /// ready tick starts a fresh interval.
    mutating func tick(_ now: Double, ready: Bool = true) {
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
