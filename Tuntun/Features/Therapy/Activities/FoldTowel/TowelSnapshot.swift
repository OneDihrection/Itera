//
//  TowelSnapshot.swift
//  Tuntun
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Foundation

enum TowelPhase { case countdown, practice }

struct TowelSnapshot {
    var phase = TowelPhase.countdown
    var instruction = "session.countdown"
    var count = 0
    var seconds = 3
    var foldIndex = 0
    var foldProgress = 0.0
    var interaction = TowelFoldSequence.Phase.approach
    var holdProgress = 0.0
    var grabID = 0
    var imageAspect = 4.0 / 3.0
    var handPosition: TherapyPoint?
    var grip = TowelFoldSequence.Grip.uncertain
    var grabPoint = TherapyPoint(x: 0.8, y: 0.5)
    var destination = TherapyPoint(x: 0.2, y: 0.5)
    var trackingMessage: String?
    /// Seconds of practice in the current set, credited only while the hand is measured.
    var practiceSeconds = 0.0
}

/// Camera-derived pinch is a visible gesture estimate, never grip force.
struct TowelHandMeasurement {
    /// Palm center (wrist plus knuckles): low-noise, it carries the hand's movement.
    let palm: TherapyPoint
    /// Thumb- and index-tip midpoint minus `palm`; `nil` unless both tips are measurable.
    /// The cursor is `palm` plus this offset, so it sits where the patient pinches.
    let pinchOffset: TherapyPoint?
    /// Thumb-tip to index-tip distance over palm length; small when pinched, `nil` when not measurable.
    let pinch: Double?

    /// Joints that contributed to this measurement; pass back as `retained` for the next frame.
    private(set) var joints: Set<Int> = []

    /// A joint enters at confidence 0.5 but stays while it keeps at least 0.35, so the cursor's
    /// joint set does not flicker (and step the cursor) when one joint hovers at the cutoff.
    init?(_ hand: HandEvidence, retained: Set<Int> = []) {
        guard hand.points.count == 21,
              hand.width.isFinite, hand.height.isFinite,
              hand.width > 0, hand.height > 0 else {
            return nil
        }

        func usable(_ index: Int) -> Bool {
            let point = hand.points[index]
            let minimum: Float = retained.contains(index) ? 0.35 : 0.5
            return point.confidence.isFinite && point.confidence >= minimum
                && point.x.isFinite && point.y.isFinite
                && (0...1).contains(point.x) && (0...1).contains(point.y)
        }

        guard usable(0) else { return nil }
        var used: Set<Int> = [0]
        // Only the thumb and index tips are needed, so the other fingers may stay relaxed or hidden.
        // Palm length (wrist to middle knuckle) makes the ratio independent of distance to the camera.
        let palmLength = hand.distance(0, 9)
        if [4, 8, 9].allSatisfy(usable), palmLength > 0.04 {
            pinch = hand.distance(4, 8) / palmLength
            used.formUnion([4, 8, 9])
        } else {
            pinch = nil
        }

        // The palm (wrist plus knuckles) still decides whether a hand is present.
        let palm = ([0] + [5, 9, 13, 17]).filter(usable)
        guard palm.count >= 3 else { return nil }
        used.formUnion(palm)

        let count = Double(palm.count)
        let center = TherapyPoint(
            x: palm.reduce(0) { $0 + hand.points[$1].x } / count,
            y: palm.reduce(0) { $0 + hand.points[$1].y } / count
        )
        self.palm = center

        // The thumb and index tips meet near their midpoint, so the offset changes little as they
        // close; the activity smooths it separately from the palm.
        if [4, 8].allSatisfy(usable) {
            used.formUnion([4, 8])
            let midpoint = TherapyPoint(
                x: (hand.points[4].x + hand.points[8].x) / 2,
                y: (hand.points[4].y + hand.points[8].y) / 2
            )
            pinchOffset = midpoint - center
        } else {
            pinchOffset = nil
        }

        joints = used
    }
}
