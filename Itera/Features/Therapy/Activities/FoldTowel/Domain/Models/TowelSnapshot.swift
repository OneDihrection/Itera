//
//  TowelSnapshot.swift
//  Itera
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
}

/// Camera-derived pinch is a visible gesture estimate, never grip force.
struct TowelHandMeasurement {
    let position: TherapyPoint
    /// Thumb-tip to index-tip distance over palm length; small when pinched, `nil` when not measurable.
    let pinch: Double?

    /// Joints that contributed to this measurement; pass back as `retained` for the next frame.
    private(set) var joints: Set<Int> = []

    /// A joint enters at confidence 0.5 but stays while it keeps at least 0.35, so the palm-center
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

        // The palm center (wrist plus knuckles) barely moves when the thumb and index close, unlike the
        // wrist alone, whose detected position can shift with the hand pose.
        let palm = ([0] + [5, 9, 13, 17]).filter(usable)
        guard palm.count >= 3 else { return nil }
        used.formUnion(palm)
        joints = used
        let count = Double(palm.count)
        position = TherapyPoint(
            x: palm.reduce(0) { $0 + hand.points[$1].x } / count,
            y: palm.reduce(0) { $0 + hand.points[$1].y } / count
        )
    }
}
