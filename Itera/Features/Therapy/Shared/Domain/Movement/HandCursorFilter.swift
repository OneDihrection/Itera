//
//  HandCursorFilter.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import Foundation

/// Adaptive low-pass filter for one hand position (a One Euro filter).
///
/// A steady hand is smoothed heavily so detector jitter disappears; a fast hand is smoothed
/// lightly so the cursor does not lag. Fold towel feeds the filtered point to both the cursor and
/// acceptance, so what the patient sees is what is scored.
struct HandCursorFilter {
    /// Cutoff in Hz at rest. Lower removes more jitter but adds lag while nearly still.
    private let minimumCutoff = 1.6
    /// How quickly the cutoff rises with speed (normalized image units per second).
    private let speedGain = 8.0
    private let derivativeCutoff = 1.0
    /// A gap longer than this means evidence was lost; the next sample starts a fresh track.
    private let maximumGap = 0.3

    private var filtered: TherapyPoint?
    private var velocity = TherapyPoint(x: 0, y: 0)
    private var timestamp: Double?

    mutating func reset() {
        filtered = nil
        velocity = TherapyPoint(x: 0, y: 0)
        timestamp = nil
    }

    /// Returns the filtered position. Non-increasing time, non-finite input or a long gap restarts
    /// the filter at the raw sample instead of blending across missing evidence.
    mutating func consume(_ value: TherapyPoint, at time: Double) -> TherapyPoint {
        guard value.x.isFinite, value.y.isFinite, time.isFinite else {
            reset()
            return value
        }

        guard let filtered, let timestamp, time > timestamp, time - timestamp <= maximumGap else {
            self.filtered = value
            self.timestamp = time
            velocity = TherapyPoint(x: 0, y: 0)
            return value
        }

        let interval = time - timestamp
        let rawVelocity = (value - filtered).scaled(1 / interval)
        let velocityAlpha = Self.alpha(cutoff: derivativeCutoff, interval: interval)
        velocity = velocity + (rawVelocity - velocity).scaled(velocityAlpha)

        let cutoff = minimumCutoff + speedGain * velocity.length
        let alpha = Self.alpha(cutoff: cutoff, interval: interval)
        let result = filtered + (value - filtered).scaled(alpha)

        self.filtered = result
        self.timestamp = time

        return result
    }

    private static func alpha(cutoff: Double, interval: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)

        return 1 / (1 + tau / interval)
    }
}
