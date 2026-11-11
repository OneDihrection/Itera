//
//  SessionDurationClock.swift
//  Itera
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

/// The long-rest reference rhythm. The short break between sets uses RestBreath.
struct LongRestBreath {
    enum Phase {
        case inhale, hold, exhale, settle
    }

    static let count = 6
    static let inhaleSeconds = 3.0
    static let holdSeconds = 2.0
    static let exhaleSeconds = 5.0
    static let settleSeconds = 2.0
    static let cycleDuration = inhaleSeconds + holdSeconds + exhaleSeconds + settleSeconds
    static let duration = Double(count) * cycleDuration

    let number: Int
    let phase: Phase
    let intensity: Double

    init(elapsed: Double) {
        let elapsed = min(max(0, elapsed), Self.duration.nextDown)
        number = Int(elapsed / Self.cycleDuration) + 1
        let position = elapsed.truncatingRemainder(dividingBy: Self.cycleDuration)
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
