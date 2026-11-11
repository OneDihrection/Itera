//
//  HandOverlaySmoother.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 02/11/2026.
//

import Foundation

/// Presentation-only adaptive filtering. Raw evidence remains the input for scoring.
///
/// Each joint passes through three stages:
/// 1. A median of the last three raw samples removes single-frame detector spikes.
/// 2. A large jump that the next frame does not confirm is held back for one frame.
/// 3. A One Euro filter follows the median trajectory: calm when the hand is still,
///    responsive when it moves.
///
/// A joint that drops out briefly keeps its last drawn position so overlays do not blink.
/// None of these presentation positions are ever fed into exercise scoring.
struct HandOverlaySmoother {
    // MARK: - Tuning

    /// How long a missing joint keeps its last drawn position.
    private static let jointBridge = 0.15
    /// Longest gap after which the filter restarts instead of gliding to the new position.
    private static let reacquireWindow = InterruptibleHold.trackingGrace
    /// Aspect-corrected jump treated as a possible outlier until the next frame confirms it.
    private static let outlierDistance = 0.18
    private static let confirmationDistance = 0.08

    // MARK: - State

    private var raw = [HandPoint?](repeating: nil, count: 21)
    private var preceding = [HandPoint?](repeating: nil, count: 21)
    private var lastValidTime = [Double?](repeating: nil, count: 21)
    private var filtered = [HandPoint?](repeating: nil, count: 21)
    private var oneEuro = [OneEuroFilter](repeating: OneEuroFilter(parameters: .handOverlay), count: 21)
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
            oneEuro[index].reset()
        }

        last = nil
    }

    mutating func consume(_ hand: HandEvidence) -> HandEvidence {
        guard hand.points.count == 21,
              hand.width.isFinite,
              hand.height.isFinite,
              hand.width > 0,
              hand.height > 0,
              hand.timestamp.isFinite else {
            reset()
            return hand
        }

        if let last, isDiscontinuous(hand, after: last) {
            reset()
        }

        let interval = hand.timestamp - (last?.timestamp ?? hand.timestamp)
        let aspect = hand.width / hand.height
        var points = hand.points

        for index in points.indices {
            points[index] = smoothedPoint(
                at: index,
                observed: points[index],
                time: hand.timestamp,
                interval: interval,
                aspect: aspect
            )
        }

        last = hand

        return HandEvidence(
            timestamp: hand.timestamp,
            generation: hand.generation,
            width: hand.width,
            height: hand.height,
            side: hand.side,
            points: points
        )
    }

    // MARK: - Filtering

    private func isDiscontinuous(_ hand: HandEvidence, after last: HandEvidence) -> Bool {
        hand.generation != last.generation
            || hand.side != last.side
            || hand.width != last.width
            || hand.height != last.height
            || hand.timestamp <= last.timestamp
            || hand.timestamp - last.timestamp > Self.reacquireWindow
    }

    private mutating func smoothedPoint(
        at index: Int,
        observed point: HandPoint,
        time: Double,
        interval: Double,
        aspect: Double
    ) -> HandPoint {
        guard Self.isUsable(point) else {
            return bridgedPoint(at: index, time: time)
        }

        defer {
            preceding[index] = raw[index]
            raw[index] = point
            lastValidTime[index] = time
        }

        let target = medianTarget(at: index, observed: point)

        guard let display = filtered[index], interval > 0 else {
            filtered[index] = target
            oneEuro[index].restart(at: TherapyPoint(x: target.x * aspect, y: target.y), time: time)
            return target
        }

        let displacement = hypot((target.x - display.x) * aspect, target.y - display.y)

        if let previous = raw[index] {
            let confirmation = hypot((target.x - previous.x) * aspect, target.y - previous.y)

            // An unconfirmed long jump is usually a detector swap; wait one frame for evidence.
            if displacement > Self.outlierDistance && confirmation > Self.confirmationDistance {
                let held = HandPoint(x: display.x, y: display.y, confidence: point.confidence)
                filtered[index] = held
                return held
            }
        }

        // Without a previous raw sample this is a reacquired joint: glide from where it was drawn.
        if raw[index] == nil, let validTime = lastValidTime[index] {
            oneEuro[index].restart(at: TherapyPoint(x: display.x * aspect, y: display.y), time: validTime)
        }

        let smoothed = oneEuro[index].consume(TherapyPoint(x: target.x * aspect, y: target.y), at: time)
        let result = HandPoint(
            x: smoothed.x / aspect,
            y: smoothed.y,
            confidence: point.confidence
        )
        filtered[index] = result
        return result
    }

    /// Keeps a joint drawn briefly after it drops out, so the skeleton does not blink.
    private mutating func bridgedPoint(at index: Int, time: Double) -> HandPoint {
        raw[index] = nil
        preceding[index] = nil

        if let display = filtered[index],
           let validTime = lastValidTime[index],
           time - validTime <= Self.jointBridge {
            return display
        }

        filtered[index] = nil
        lastValidTime[index] = nil
        return HandPoint(x: 0, y: 0, confidence: 0)
    }

    private func medianTarget(at index: Int, observed point: HandPoint) -> HandPoint {
        guard let previous = raw[index], let older = preceding[index] else {
            return point
        }

        return HandPoint(
            x: Self.median(point.x, previous.x, older.x),
            y: Self.median(point.y, previous.y, older.y),
            confidence: point.confidence
        )
    }

    /// Matches the lowest confidence scoring accepts (forearm rotation, touching fingertips),
    /// so a joint that is scored is also drawn instead of blinking out.
    private static func isUsable(_ point: HandPoint) -> Bool {
        point.confidence >= 0.3
            && point.x.isFinite
            && point.y.isFinite
            && (0...1).contains(point.x)
            && (0...1).contains(point.y)
    }

    private static func median(_ first: Double, _ second: Double, _ third: Double) -> Double {
        max(min(first, second), min(max(first, second), third))
    }
}
