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

/// Camera-derived curl is a visible gesture estimate, never grip force.
struct TowelHandMeasurement {
    let position: TherapyPoint
    let curl: Double?

    init?(_ hand: HandEvidence) {
        guard hand.points.count == 21,
              hand.width.isFinite, hand.height.isFinite,
              hand.width > 0, hand.height > 0 else {
            return nil
        }

        func usable(_ index: Int) -> Bool {
            let point = hand.points[index]
            return point.confidence.isFinite && point.confidence >= 0.5
                && point.x.isFinite && point.y.isFinite
                && (0...1).contains(point.x) && (0...1).contains(point.y)
        }

        guard usable(0) else { return nil }
        let chains = [5, 9, 13, 17].filter {
            [$0, $0 + 1, $0 + 2].allSatisfy(usable)
                && hand.angle($0, $0 + 1, $0 + 2).isFinite
        }
        curl = chains.count >= 2
            ? chains.reduce(0) { $0 + (180 - hand.angle($1, $1 + 1, $1 + 2)) / 180 } / Double(chains.count)
            : nil
        position = TherapyPoint(x: hand.points[0].x, y: hand.points[0].y)
    }
}
