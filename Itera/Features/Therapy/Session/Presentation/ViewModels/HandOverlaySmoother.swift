//
//  HandOverlaySmoother.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 02/11/2026.
//

import Foundation

/// Presentation-only adaptive filtering. Raw evidence remains the input for scoring.
struct HandOverlaySmoother {
    private var raw = [HandPoint?](repeating: nil, count: 21)
    private var filtered = [HandPoint?](repeating: nil, count: 21)
    private var last: HandEvidence?

    mutating func reset() {
        guard last != nil else {
            return
        }
        for index in raw.indices {
            raw[index] = nil
            filtered[index] = nil
        }
        last = nil
    }

    mutating func consume(_ hand: HandEvidence) -> HandEvidence {
        guard hand.points.count == 21, hand.width.isFinite, hand.height.isFinite,
              hand.width > 0, hand.height > 0, hand.timestamp.isFinite else {
            reset()
            return hand
        }
        if let last, hand.generation != last.generation || hand.side != last.side
            || hand.width != last.width || hand.height != last.height
            || hand.timestamp <= last.timestamp || hand.timestamp - last.timestamp > 0.3
        {
            reset()
        }
        let interval = hand.timestamp - (last?.timestamp ?? hand.timestamp)
        let aspect = hand.width / hand.height
        var points = hand.points
        for index in points.indices {
            let point = points[index]
            guard point.confidence >= 0.5, point.x.isFinite, point.y.isFinite,
                  (0...1).contains(point.x), (0...1).contains(point.y) else {
                raw[index] = nil
                filtered[index] = nil
                continue
            }
            if let previous = raw[index], let display = filtered[index], interval > 0 {
                let speed = hypot((point.x - previous.x) * aspect, point.y - previous.y) / interval
                let cutoff = 2 + min(8, max(0, speed - 0.8) * 3)
                let alpha = 1 - exp(-2 * .pi * cutoff * interval)
                points[index] = HandPoint(
                    x: display.x + alpha * (point.x - display.x),
                    y: display.y + alpha * (point.y - display.y),
                    confidence: point.confidence
                )
            }
            raw[index] = point
            filtered[index] = points[index]
        }
        last = hand
        return HandEvidence(
            timestamp: hand.timestamp, generation: hand.generation,
            width: hand.width, height: hand.height, side: hand.side, points: points
        )
    }
}
