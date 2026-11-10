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
    private let minimumCutoff = 1.0
    /// How quickly the cutoff rises with speed (normalized image units per second).
    private let speedGain = 10.0
    private let derivativeCutoff = 1.0
    /// A gap longer than this means evidence was lost; the next sample starts a fresh track.
    private let maximumGap = 0.3

    private var filtered: TherapyPoint?
    private var previousRaw: TherapyPoint?
    private var velocity = TherapyPoint(x: 0, y: 0)
    private var timestamp: Double?

    mutating func reset() {
        filtered = nil
        previousRaw = nil
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

        guard let filtered, let previousRaw, let timestamp, time > timestamp, time - timestamp <= maximumGap else {
            self.filtered = value
            self.previousRaw = value
            self.timestamp = time
            velocity = TherapyPoint(x: 0, y: 0)
            return value
        }

        let interval = time - timestamp
        // Speed comes from consecutive raw samples; measuring against the lagging filtered value
        // would bias the estimate and make the cutoff react late.
        let rawVelocity = (value - previousRaw).scaled(1 / interval)
        let velocityAlpha = Self.alpha(cutoff: derivativeCutoff, interval: interval)
        velocity = velocity + (rawVelocity - velocity).scaled(velocityAlpha)

        let cutoff = minimumCutoff + speedGain * velocity.length
        let alpha = Self.alpha(cutoff: cutoff, interval: interval)
        let result = filtered + (value - filtered).scaled(alpha)

        self.filtered = result
        self.previousRaw = value
        self.timestamp = time

        return result
    }

    fileprivate static func alpha(cutoff: Double, interval: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)

        return 1 / (1 + tau / interval)
    }
}

/// Adaptive low-pass filter for a single measurement such as the pinch ratio.
///
/// Detector noise on the thumb and index tips would otherwise flip grab and release on one
/// frame; a deliberate pinch still passes quickly because the cutoff rises with speed.
struct ScalarCursorFilter {
    private let minimumCutoff = 2.0
    private let speedGain = 1.5
    private let derivativeCutoff = 1.0
    private let maximumGap = 0.3

    private var filtered: Double?
    private var previousRaw: Double?
    private var velocity = 0.0
    private var timestamp: Double?

    mutating func reset() {
        filtered = nil
        previousRaw = nil
        velocity = 0
        timestamp = nil
    }

    mutating func consume(_ value: Double, at time: Double) -> Double {
        guard value.isFinite, time.isFinite else {
            reset()
            return value
        }

        guard let filtered, let previousRaw, let timestamp, time > timestamp, time - timestamp <= maximumGap else {
            self.filtered = value
            self.previousRaw = value
            self.timestamp = time
            velocity = 0
            return value
        }

        let interval = time - timestamp
        let rawVelocity = (value - previousRaw) / interval
        velocity += (rawVelocity - velocity) * HandCursorFilter.alpha(cutoff: derivativeCutoff, interval: interval)

        let cutoff = minimumCutoff + speedGain * abs(velocity)
        let result = filtered + (value - filtered) * HandCursorFilter.alpha(cutoff: cutoff, interval: interval)

        self.filtered = result
        self.previousRaw = value
        self.timestamp = time

        return result
    }
}
