//
//  TowelSpeechPolicy.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import Foundation

/// Decides when live towel practice speaks.
///
/// Sounds and the on-screen step strip already mark every grab, fold and completion, so speech
/// would only add load. The policy allows one cue when practice begins and, if the patient has
/// made no progress at the handle for a while, a single reminder until they next make progress. It never speaks for phase
/// changes inside a fold, recovery or tracking loss. It has no effect on mechanics or text.
struct TowelSpeechPolicy {
    /// Time at the handle without a grab before a reminder is spoken.
    static let stuckDelay = 8.0
    /// Minimum time between spoken cues, so a reminder never follows closely on another.
    static let quietPeriod = 20.0
    /// Ticks stop while paused or waiting for the camera; a longer gap restarts the timers.
    private static let maximumTickGap = 1.0

    private var started = false
    private var reminded = false
    private var signature: Signature?
    private var lastProgress = 0.0
    private var lastSpoken = 0.0
    private var lastCall = 0.0

    private struct Signature: Equatable {
        let grabID: Int
        let foldIndex: Int
        let count: Int
    }

    mutating func reset() {
        self = TowelSpeechPolicy()
    }

    /// Call on every engine tick while the towel is live. Returns whether to speak its current cue.
    mutating func shouldSpeak(_ snapshot: TowelSnapshot, now: Double) -> Bool {
        guard snapshot.phase == .practice else {
            reset()
            return false
        }

        defer { lastCall = now }

        guard started else {
            started = true
            signature = Signature(grabID: snapshot.grabID, foldIndex: snapshot.foldIndex, count: snapshot.count)
            lastProgress = now
            lastSpoken = now
            return true
        }

        if now - lastCall > Self.maximumTickGap {
            lastProgress = now
        }

        let current = Signature(grabID: snapshot.grabID, foldIndex: snapshot.foldIndex, count: snapshot.count)

        if current != signature {
            signature = current
            lastProgress = now
            reminded = false
            return false
        }

        guard !reminded,
              snapshot.interaction == .approach,
              now - lastProgress >= Self.stuckDelay,
              now - lastSpoken >= Self.quietPeriod else {
            return false
        }

        lastSpoken = now
        reminded = true

        return true
    }
}
