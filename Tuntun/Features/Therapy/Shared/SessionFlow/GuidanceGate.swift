//
//  GuidanceGate.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation

/// The identity of one spoken cue and what it still waits for: its narration, its on-screen
/// reading and a watchdog for narration that never reports back.
///
/// A completion or reading callback counts only when it carries this cue's identity, and a
/// narration completes once. A cue replayed after a pause or camera wait gets a new gate, so
/// callbacks from the cue it replaced are ignored.
struct GuidanceGate: Equatable {
    let id: UUID
    let startedAt: Double
    /// When the cue counts as finished without a completion. Cleared once the narration completes.
    private(set) var watchdogAt: Double?
    private(set) var narrated = false
    private(set) var read: Bool

    /// - Parameters:
    ///   - watchdog: seconds after `startedAt` before the cue is treated as finished.
    ///   - read: false when the cue is also shown as a card that must be read before advancing.
    init(id: UUID = UUID(), startedAt: Double, watchdog: Double, read: Bool = true) {
        self.id = id
        self.startedAt = startedAt
        watchdogAt = startedAt + watchdog
        self.read = read
    }

    /// Records the narration as finished. Returns false for another cue's identity or a repeat.
    mutating func complete(_ id: UUID) -> Bool {
        guard id == self.id, !narrated else {
            return false
        }

        narrated = true
        watchdogAt = nil
        return true
    }

    /// Records whether the card has been read. Returns false for another cue's identity.
    mutating func reading(_ id: UUID, done: Bool) -> Bool {
        guard id == self.id else {
            return false
        }

        read = done
        return true
    }

    /// True once the watchdog has passed without a completion.
    func expired(at now: Double) -> Bool {
        guard let watchdogAt else {
            return false
        }

        return now >= watchdogAt
    }
}
