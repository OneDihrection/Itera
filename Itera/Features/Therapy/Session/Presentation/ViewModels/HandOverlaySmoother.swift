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
    private var preceding = [HandPoint?](repeating: nil, count: 21)
    private var lastValidTime = [Double?](repeating: nil, count: 21)
    private var filtered = [HandPoint?](repeating: nil, count: 21)
    private var last: HandEvidence?

    mutating func reset() {
        guard last != nil else {
            return
        }
        for index in raw.indices {
            raw[index] = nil
            preceding[index] = nil
            lastValidTime[index] = nil
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
                preceding[index] = nil
                // A short visual bridge avoids blinking; it is never fed into exercise scoring.
                if let display = filtered[index], let validTime = lastValidTime[index],
                   hand.timestamp - validTime <= 0.15 {
                    points[index] = display
                } else {
                    filtered[index] = nil
                    lastValidTime[index] = nil
                    points[index] = HandPoint(x: 0, y: 0, confidence: 0)
                }
                continue
            }
            var target = point
            if let previous = raw[index], let older = preceding[index] {
                target = HandPoint(
                    x: median(point.x, previous.x, older.x),
                    y: median(point.y, previous.y, older.y),
                    confidence: point.confidence
                )
            }
            if let previous = raw[index], let display = filtered[index], interval > 0 {
                let displacement = hypot((target.x - display.x) * aspect, target.y - display.y)
                let confirmationDistance = hypot((target.x - previous.x) * aspect, target.y - previous.y)
                if displacement > 0.18 && confirmationDistance > 0.08 {
                    points[index] = HandPoint(x: display.x, y: display.y, confidence: point.confidence)
                } else {
                    // Adapt to the median trajectory, rather than amplifying raw detector noise.
                    let speed = displacement / interval
                    let cutoff = 1.2 + min(3, max(0, speed - 0.25) * 1.5)
                    let alpha = 1 - exp(-2 * .pi * cutoff * interval)
                    points[index] = HandPoint(
                        x: display.x + alpha * (target.x - display.x),
                        y: display.y + alpha * (target.y - display.y),
                        confidence: point.confidence
                    )
                }
            } else if let display = filtered[index], interval > 0 {
                // Reacquiring a joint inside the visual grace must not snap to its raw position.
                let alpha = 1 - exp(-2 * .pi * 1.2 * interval)
                points[index] = HandPoint(
                    x: display.x + alpha * (target.x - display.x),
                    y: display.y + alpha * (target.y - display.y),
                    confidence: point.confidence
                )
            }
            preceding[index] = raw[index]
            raw[index] = point
            filtered[index] = points[index]
            lastValidTime[index] = hand.timestamp
        }
        last = hand
        return HandEvidence(
            timestamp: hand.timestamp, generation: hand.generation,
            width: hand.width, height: hand.height, side: hand.side, points: points
        )
    }

    private func median(_ first: Double, _ second: Double, _ third: Double) -> Double {
        max(min(first, second), min(max(first, second), third))
    }

}
