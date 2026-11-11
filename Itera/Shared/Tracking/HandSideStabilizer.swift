//
//  HandSideStabilizer.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 10/11/2026.
//

import Foundation

/// Keeps the tracked hand's left/right reading steady.
///
/// Vision's chirality flips for single frames, or reads as unknown, while fingers curl or touch
/// (a thumb meeting a fingertip is the worst case). Each flip used to reject the frame as "the
/// other hand", which froze the hold and hid the overlay. `HandSubjectSelector` already locks onto
/// one hand, so here chirality is a vote: the confirmed side changes only after the detector has
/// disagreed for about half a second, and unknown readings keep the confirmed side.
struct HandSideStabilizer {
    /// Time constant of the agreement vote. A sustained disagreement flips the side after ~0.5 s.
    private static let voteTimeConstant = 0.6
    /// The vote must fall below this before the side changes.
    private static let switchThreshold = -0.3
    /// After a gap this long the hand may be a different one, so the side is read afresh.
    private static let forgetAfter = InterruptibleHold.trackingGrace

    private var confirmed: HandSide?
    /// +1 when recent frames agree with `confirmed`, -1 when they disagree.
    private var agreement = 1.0
    private var lastTime: Double?
    private var generation: UUID?

    mutating func reset() {
        confirmed = nil
        agreement = 1
        lastTime = nil
        generation = nil
    }

    /// Returns the hand with its side replaced by the stable reading.
    mutating func stabilize(_ hand: HandEvidence) -> HandEvidence {
        let interval = hand.timestamp - (lastTime ?? hand.timestamp)

        if hand.generation != generation || interval < 0 || interval > Self.forgetAfter {
            reset()
            generation = hand.generation
        }

        lastTime = hand.timestamp

        // The first reading is only tentative (a neutral vote), so a wrong first frame is
        // corrected within a few frames instead of being trusted.
        guard let confirmed else {
            self.confirmed = hand.side
            agreement = 0
            return hand
        }

        guard let reported = hand.side else {
            return hand.assigning(side: confirmed)
        }

        let sample = reported == confirmed ? 1.0 : -1.0
        let blend = 1 - exp(-max(0, interval) / Self.voteTimeConstant)
        agreement += (sample - agreement) * blend

        guard agreement < Self.switchThreshold else {
            return hand.assigning(side: confirmed)
        }

        self.confirmed = reported
        agreement = 1

        return hand
    }
}
