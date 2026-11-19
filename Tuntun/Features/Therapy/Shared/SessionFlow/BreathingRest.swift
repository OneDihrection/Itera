//
//  BreathingRest.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation

/// The scripted short rest between sets: an optional opening, three breaths of inhale, hold and
/// exhale, a quiet stretch, and a closing. Every spoken step waits for its own narration and its
/// minimum time, so a slow Marizka recording is never cut off by the next cue. Pauses and unready
/// time earn no elapsed time.
///
/// The approved wording always says three breaths, so the plan's short rest (`minimumSeconds`)
/// cannot change their number. Instead the quiet step after the last exhale lasts until the whole
/// rest has reached it; a short rest shorter than the script keeps the script's own length.
///
/// Used by the Indonesian arm-raise script (`SessionEngine`) and thumb-opposition script
/// (`FingerSessionViewModel`). The timed rest keeps its stateless rhythm, `RestBreath`.
struct BreathingRest: Equatable {
    /// The silent step after the last exhale.
    private static let quietStep = 10
    private static let closingStep = 11

    private(set) var step: Int
    private(set) var elapsed = 0.0
    /// Credited seconds since the rest began, across every step.
    private(set) var totalElapsed = 0.0
    private let minimumSeconds: Double
    private var lastTick: Double?
    private(set) var narrationFinished = false

    var finished: Bool { step > Self.closingStep }

    /// "rest.opening" says set one is done and set two follows, so later rests start with the
    /// first breath.
    ///
    /// - Parameter minimumSeconds: the plan's short rest; the rest lasts at least this long.
    init(opensAfterFirstSet: Bool, minimumSeconds: Double) {
        step = opensAfterFirstSet ? 0 : 1
        self.minimumSeconds = minimumSeconds
    }

    /// The recorded line of the current step, or nil during the quiet step, which speaks nothing.
    var key: String? {
        if step == 0 {
            return "rest.opening"
        }

        if step == Self.quietStep {
            return nil
        }

        if step >= Self.closingStep {
            return "rest.closing"
        }

        let breath = (step - 1) / 3 + 1

        switch (step - 1) % 3 {
        case 0: return "rest.inhale.\(breath)"
        case 1: return breath == 1 ? "rest.hold.first" : "rest.hold"
        default: return breath == 3 ? "rest.exhale.last" : "rest.exhale"
        }
    }

    /// The on-screen cue: the recorded line with the script's `prefix`, or during the quiet
    /// step the unspoken breathing rhythm of the timed rest.
    func cueKey(prefix: String) -> String {
        guard let key else {
            return RestBreath(elapsed: elapsed).phase.key
        }

        return prefix + key
    }

    /// Minimum seconds of the current step: inhale 6, hold 2, exhale 3; the quiet step whatever
    /// the short rest still needs; opening and closing 0.
    private var duration: Double {
        if step == Self.quietStep {
            return max(0, minimumSeconds - (totalElapsed - elapsed))
        }

        guard step > 0, step < Self.quietStep else {
            return 0
        }

        switch (step - 1) % 3 {
        case 0: return 6
        case 1: return 2
        default: return 3
        }
    }

    var intensity: Double {
        if step == Self.quietStep {
            return RestBreath(elapsed: elapsed).intensity
        }

        guard step > 0, step < Self.quietStep else {
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

        let credit = min(0.2, max(0, now - (lastTick ?? now)))
        elapsed += credit
        totalElapsed += credit
        lastTick = now

        // The quiet step has no narration to wait for.
        guard elapsed >= duration, narrationFinished || key == nil else {
            return
        }

        step += 1
        elapsed = 0
        narrationFinished = false
    }
}
