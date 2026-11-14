//
//  AngleHoldEstimator.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

/// Turns a jittery stream of per-frame angles into readings worth reporting.
///
/// A reading counts only while the joint is held still: at least `minimumSpan` seconds of
/// samples inside one second that stay within `tolerance` degrees. The held value is their
/// median, so one misdetected frame cannot set a record. Only held values update the range,
/// which is why a fast swing through an extreme never becomes the patient's maximum.
struct AngleHoldEstimator {
    static let window = 1.0
    static let minimumSpan = 0.8
    /// The spread allowed while holding. 2D landmarks jitter by about two to three degrees.
    static let tolerance = 6.0
    /// A longer gap between frames starts a new hold, matching the 300 ms freshness rule.
    static let maximumGap = 0.3

    private var samples: [(time: Double, degrees: Double)] = []
    private var source: AngleSource?

    /// The current held angle, or nil while moving or without evidence.
    private(set) var held: Double?
    /// The smallest and largest held angles since the last reset: the measured range of motion.
    private(set) var minimum: Double?
    private(set) var maximum: Double?

    /// How far through the hold the current stillness is, from 0 to 1, for a progress ring.
    private(set) var holdProgress = 0.0

    mutating func consume(_ sample: AngleSample) {
        let restarts = source != sample.source
            || samples.last.map { sample.timestamp - $0.time > Self.maximumGap || sample.timestamp <= $0.time } ?? false

        if restarts {
            clearHold()
        }

        source = sample.source
        samples.append((sample.timestamp, sample.degrees))
        samples.removeAll { sample.timestamp - $0.time > Self.window }

        let values = samples.map(\.degrees)

        guard let low = values.min(), let high = values.max(), high - low <= Self.tolerance else {
            // Moving: keep only the newest sample so the next hold starts from here.
            samples = [samples[samples.count - 1]]
            held = nil
            holdProgress = 0
            return
        }

        let span = sample.timestamp - samples[0].time
        holdProgress = min(1, span / Self.minimumSpan)

        guard span >= Self.minimumSpan else {
            held = nil
            return
        }

        let value = Self.median(values)
        held = value
        minimum = min(minimum ?? value, value)
        maximum = max(maximum ?? value, value)
    }

    /// No usable evidence this frame: the hold ends, the recorded range stays.
    mutating func missing() {
        clearHold()
    }

    mutating func reset() {
        clearHold()
        minimum = nil
        maximum = nil
    }

    private mutating func clearHold() {
        samples.removeAll(keepingCapacity: true)
        source = nil
        held = nil
        holdProgress = 0
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2

        guard sorted.count.isMultiple(of: 2) else {
            return sorted[middle]
        }

        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}
