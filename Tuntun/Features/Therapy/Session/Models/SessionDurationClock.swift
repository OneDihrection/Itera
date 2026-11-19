//
//  SessionDurationClock.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 02/11/2026.
//

import Foundation

/// On-screen session duration includes guidance/rest/tracking waits, excluding explicit pauses.
/// It is separate from evidence-credited practice time in exercise results.
struct SessionDurationClock {
    private var accumulated = 0.0
    private var runningSince: Double?

    mutating func resume(at now: Double) {
        guard now.isFinite, runningSince == nil else {
            return
        }
        runningSince = now
    }

    mutating func pause(at now: Double) {
        guard now.isFinite, let runningSince else {
            return
        }
        accumulated += max(0, now - runningSince)
        self.runningSince = nil
    }

    func elapsed(at now: Double) -> Double {
        guard now.isFinite, let runningSince else {
            return accumulated
        }
        return accumulated + max(0, now - runningSince)
    }
}

/// A visual and spoken rhythm sampled from the session's existing rest clock.
struct RestBreath: Equatable {
    enum Phase: Equatable {
        case inhale
        case exhale

        var key: String {
            switch self {
            case .inhale: return "rest.breath.inhale"
            case .exhale: return "rest.breath.exhale"
            }
        }
    }

    let phase: Phase
    let intensity: Double

    init(elapsed: Double) {
        let inhale = 6.0
        let exhale = 3.0
        let position = max(0, elapsed).truncatingRemainder(dividingBy: inhale + exhale)
        let expansion: Double
        if position < inhale {
            phase = .inhale
            expansion = position / inhale
        } else {
            phase = .exhale
            expansion = 1 - (position - inhale) / exhale
        }
        intensity = 0.25 + 0.75 * (1 - cos(expansion * .pi)) / 2
    }
}

/// The long-rest reference rhythm: `count` breaths of inhale, hold, exhale and settle. The
/// count is the plan's long-rest setting. The short break between sets uses RestBreath.
struct LongRestBreath {
    enum Phase {
        case inhale, hold, exhale, settle
    }

    static let inhaleSeconds = 3.0
    static let holdSeconds = 2.0
    static let exhaleSeconds = 5.0
    static let settleSeconds = 2.0
    static let cycleDuration = inhaleSeconds + holdSeconds + exhaleSeconds + settleSeconds
    /// How long the spoken "once more" before the last inhale keeps its own cue.
    static let lastPrefaceSeconds = 1.4

    static func duration(count: Int) -> Double {
        Double(count) * cycleDuration
    }

    /// The end of the current spoken phase, including “once more” before the last inhale.
    /// A caller can freeze here until its identified narration completes without cutting it off.
    static func narrationBoundary(at elapsed: Double, count: Int) -> Double {
        let breath = Self(elapsed: elapsed, count: count)
        let start = Double(breath.number - 1) * cycleDuration

        switch breath.phase {
        case .inhale:
            let isLastPreface = breath.isLast && elapsed - start < lastPrefaceSeconds
            return start + (isLastPreface ? lastPrefaceSeconds : inhaleSeconds)
        case .hold:
            return start + inhaleSeconds + holdSeconds
        case .exhale:
            return start + cycleDuration - settleSeconds
        case .settle:
            return start + cycleDuration
        }
    }

    let count: Int
    let number: Int
    let phase: Phase
    let intensity: Double
    /// Seconds since this breath began.
    let position: Double

    var isLast: Bool {
        number == count
    }

    /// Breaths still to come, this one included.
    var remaining: Int {
        count - number + 1
    }

    init(elapsed: Double, count: Int) {
        let count = max(1, count)
        let elapsed = min(max(0, elapsed), Self.duration(count: count).nextDown)
        self.count = count
        number = Int(elapsed / Self.cycleDuration) + 1
        let position = elapsed.truncatingRemainder(dividingBy: Self.cycleDuration)
        self.position = position
        let exhaleStart = Self.inhaleSeconds + Self.holdSeconds
        let settleStart = exhaleStart + Self.exhaleSeconds
        let expansion: Double

        switch position {
        case ..<Self.inhaleSeconds:
            phase = .inhale
            expansion = position / Self.inhaleSeconds
        case ..<exhaleStart:
            phase = .hold
            expansion = 1
        case ..<settleStart:
            phase = .exhale
            expansion = 1 - (position - exhaleStart) / Self.exhaleSeconds
        default:
            phase = .settle
            expansion = 0
        }

        intensity = 0.25 + 0.75 * (1 - cos(expansion * .pi)) / 2
    }
}
