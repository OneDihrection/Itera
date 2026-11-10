//
//  OneEuroFilter.swift
//  Itera
//
//  Created by dimaswisodewo on 10/11/2026.
//

import Foundation

/// Tuning for a `OneEuroFilter`. Distances are in normalized image-height units.
struct OneEuroParameters {
    /// Cutoff in Hz at rest. Lower removes more jitter but adds lag while nearly still.
    let minimumCutoff: Double
    /// How quickly the cutoff rises with speed (image heights per second).
    let speedGain: Double
    let derivativeCutoff: Double

    /// Body joints that drive acceptance, so lag is kept small while moving.
    static let bodyJoint = OneEuroParameters(minimumCutoff: 1.0, speedGain: 6, derivativeCutoff: 1.0)
    /// Finger overlay joints, applied after the median and outlier stages.
    static let handOverlay = OneEuroParameters(minimumCutoff: 1.2, speedGain: 3, derivativeCutoff: 1.0)
}

/// Adaptive low-pass filter for one 2D point (a One Euro filter): heavy smoothing at rest so
/// detector jitter disappears, light smoothing while moving so the point does not lag.
///
/// Speed is measured between consecutive raw samples. A gap over 0.3 s, non-finite input or
/// non-increasing time restarts the filter at the raw sample instead of blending across missing
/// evidence.
struct OneEuroFilter {
    private let parameters: OneEuroParameters
    private let maximumGap = 0.3

    private var filtered: TherapyPoint?
    private var previousRaw: TherapyPoint?
    private var velocity = TherapyPoint(x: 0, y: 0)
    private var timestamp: Double?

    init(parameters: OneEuroParameters) {
        self.parameters = parameters
    }

    mutating func reset() {
        filtered = nil
        previousRaw = nil
        velocity = TherapyPoint(x: 0, y: 0)
        timestamp = nil
    }

    /// Starts a track at `point` with no velocity, so the next sample glides from it.
    mutating func restart(at point: TherapyPoint, time: Double) {
        filtered = point
        previousRaw = point
        velocity = TherapyPoint(x: 0, y: 0)
        timestamp = time
    }

    mutating func consume(_ value: TherapyPoint, at time: Double) -> TherapyPoint {
        guard value.x.isFinite, value.y.isFinite, time.isFinite else {
            reset()
            return value
        }

        guard let filtered, let previousRaw, let timestamp, time > timestamp, time - timestamp <= maximumGap else {
            restart(at: value, time: time)
            return value
        }

        let interval = time - timestamp
        let rawVelocity = (value - previousRaw).scaled(1 / interval)
        let velocityAlpha = Self.alpha(cutoff: parameters.derivativeCutoff, interval: interval)
        velocity = velocity + (rawVelocity - velocity).scaled(velocityAlpha)

        let cutoff = parameters.minimumCutoff + parameters.speedGain * velocity.length
        let result = filtered + (value - filtered).scaled(Self.alpha(cutoff: cutoff, interval: interval))

        self.filtered = result
        self.previousRaw = value
        self.timestamp = time

        return result
    }

    private static func alpha(cutoff: Double, interval: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)

        return 1 / (1 + tau / interval)
    }
}
