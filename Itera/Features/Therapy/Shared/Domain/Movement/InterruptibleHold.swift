//
//  InterruptibleHold.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import Foundation

/// Hold time credited only from fresh evidence that the patient is in the requested position.
///
/// A short interruption — a bystander crossing the camera, a dropped frame, a brief tracker
/// miss, or a one-frame wobble across a zone edge — freezes the hold instead of clearing it.
/// The interrupted interval itself is never credited, so the patient still has to hold for
/// the full duration. Only an interruption that outlasts its grace clears the hold.
///
/// This is the single owner of hold-time arithmetic for the finger and balance activities
/// (movement capture applies the same rules in `StableHold`), so bubble timers agree.
struct InterruptibleHold {
    /// Longest tracking loss a hold survives (bystanders, occlusion, missing joints).
    static let trackingGrace = 1.5
    /// Longest time the tracked point may sit outside its zone before the hold clears.
    /// Kept short: leaving the zone means the movement is no longer being performed.
    static let zoneExitGrace = 0.4
    /// Longest interval between two fresh in-zone samples that still earns credit.
    static let maximumCreditedStep = 0.3

    private(set) var elapsed = 0.0
    private(set) var isHolding = false
    private var lastEvidence: Double?
    private var interruptedSince: Double?

    var isInterrupted: Bool {
        interruptedSince != nil
    }

    func progress(duration: Double) -> Double {
        guard duration > 0 else {
            return 1
        }

        return min(1, max(0, elapsed / duration))
    }

    func remaining(duration: Double) -> Double {
        max(0, duration - elapsed)
    }

    /// Credits fresh in-zone evidence observed at `time`.
    ///
    /// The first sample starts the hold without credit. After an interruption, the first
    /// sample resumes the hold, again without credit for the interrupted interval.
    mutating func credit(at time: Double, maximumStep: Double = maximumCreditedStep) {
        guard time.isFinite else {
            return
        }

        defer {
            lastEvidence = time
            isHolding = true
            interruptedSince = nil
        }

        guard isHolding,
              interruptedSince == nil,
              let lastEvidence,
              time > lastEvidence else {
            return
        }

        let step = time - lastEvidence

        if step <= maximumStep {
            elapsed += step
        }
    }

    /// Records that in-zone evidence is missing at `time`.
    ///
    /// - Returns: `true` while the hold survives the interruption, `false` once the
    ///   interruption has lasted longer than `grace` and the hold has been cleared.
    @discardableResult
    mutating func interrupt(at time: Double, grace: Double) -> Bool {
        guard isHolding, time.isFinite else {
            return false
        }

        let since = interruptedSince ?? time
        interruptedSince = since

        guard time - since <= grace else {
            reset()
            return false
        }

        return true
    }

    mutating func reset() {
        self = InterruptibleHold()
    }
}
