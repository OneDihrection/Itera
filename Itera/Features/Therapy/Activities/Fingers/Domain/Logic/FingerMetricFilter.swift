//
//  FingerMetricFilter.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 10/11/2026.
//

import Foundation

/// Adaptive low-pass filter for one finger movement metric (a scalar One Euro filter).
///
/// Vision's fingertip positions jitter from frame to frame, most of all when fingers touch or
/// curl. Unfiltered, that jitter pushed a held pose in and out of its zone and froze or restarted
/// the hold timer. A still hand is smoothed heavily; a moving hand lightly, so arrival is not
/// delayed. The filter never blends across missing evidence: a gap, non-increasing time or a
/// non-finite value restarts it at the raw sample.
struct FingerMetricFilter {
    /// Cutoff in Hz while the metric is steady. Lower removes more jitter but adds lag.
    private static let minimumCutoff = 1.2
    /// Extra cutoff per metric unit per second of change, so real movement is followed quickly.
    private static let speedGain = 1.5
    private static let derivativeCutoff = 1.0
    /// A longer gap means evidence was lost; the next sample starts a fresh track.
    private static let maximumGap = 0.3

    private var filtered: Double?
    private var velocity = 0.0
    private var timestamp: Double?

    mutating func reset() {
        filtered = nil
        velocity = 0
        timestamp = nil
    }

    mutating func consume(_ value: Double, at time: Double) -> Double {
        guard value.isFinite, time.isFinite else {
            reset()
            return value
        }

        guard let filtered,
              let timestamp,
              time > timestamp,
              time - timestamp <= Self.maximumGap else {
            self.filtered = value
            self.timestamp = time
            velocity = 0
            return value
        }

        let interval = time - timestamp
        let rawVelocity = (value - filtered) / interval
        velocity += (rawVelocity - velocity) * Self.alpha(cutoff: Self.derivativeCutoff, interval: interval)

        let cutoff = Self.minimumCutoff + Self.speedGain * abs(velocity)
        let result = filtered + (value - filtered) * Self.alpha(cutoff: cutoff, interval: interval)

        self.filtered = result
        self.timestamp = time

        return result
    }

    private static func alpha(cutoff: Double, interval: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)

        return 1 / (1 + tau / interval)
    }
}
