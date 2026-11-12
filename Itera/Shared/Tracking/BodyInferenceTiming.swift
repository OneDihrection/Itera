//
//  BodyInferenceTiming.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import Foundation

/// Rolling per-stage timing of body inference, logged as one summary line every few seconds.
///
/// Shows where a frame's age comes from: padding, Vision, or the wait before delivery. This
/// covers the capture-to-publication age and stale-observation record of the performance
/// acceptance checks. Storage is preallocated, so recording a frame never allocates.
///
/// Not thread-safe: owned and used by the tracking queue only.
struct BodyInferenceTiming {
    /// One fixed-size window of the most recent samples, in seconds.
    private struct Window {
        private var samples: [Double]
        private var next = 0
        private(set) var count = 0

        init(capacity: Int) {
            samples = Array(repeating: 0, count: capacity)
        }

        mutating func add(_ value: Double) {
            samples[next] = value
            next = (next + 1) % samples.count
            count = min(count + 1, samples.count)
        }

        /// Sorted copy of the filled part; only built when a summary is logged.
        func sorted() -> [Double] {
            samples.prefix(count).sorted()
        }
    }

    private static let capacity = 300
    private static let logInterval = 10.0

    private var pad = Window(capacity: capacity)
    private var vision = Window(capacity: capacity)
    private var age = Window(capacity: capacity)
    private var dropped = 0
    private var paddedFrames = 0
    private var frames = 0
    private var lastLog: Double?

    /// Records one frame that finished inference. `padding` is nil when the frame was not padded.
    mutating func record(padding: Double?, vision visionTime: Double, age frameAge: Double, now: Double) {
        if let padding {
            pad.add(padding)
            paddedFrames += 1
        }

        vision.add(visionTime)
        age.add(frameAge)
        frames += 1
        logIfDue(now: now)
    }

    /// Records a frame discarded because it was too old to show.
    mutating func recordDropped(now: Double) {
        dropped += 1
        logIfDue(now: now)
    }

    private mutating func logIfDue(now: Double) {
        guard let lastLog else {
            self.lastLog = now
            return
        }

        guard now - lastLog >= Self.logInterval, frames > 0 else {
            return
        }

        let ages = age.sorted()
        NSLog(
            "Body inference timing ms pad p50=%.1f p95=%.1f vision p50=%.1f p95=%.1f age p50=%.1f p95=%.1f max=%.1f frames=%d padded=%d dropped=%d",
            Self.percentile(pad.sorted(), 0.5),
            Self.percentile(pad.sorted(), 0.95),
            Self.percentile(vision.sorted(), 0.5),
            Self.percentile(vision.sorted(), 0.95),
            Self.percentile(ages, 0.5),
            Self.percentile(ages, 0.95),
            (ages.last ?? 0) * 1000,
            frames,
            paddedFrames,
            dropped
        )

        self.lastLog = now
        frames = 0
        paddedFrames = 0
        dropped = 0
    }

    /// Milliseconds at fraction `p` of an ascending list; 0 when empty.
    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else {
            return 0
        }

        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
        return sorted[index] * 1000
    }
}
