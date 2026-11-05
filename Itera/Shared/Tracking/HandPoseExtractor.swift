//
//  HandPoseExtractor.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Vision
import Foundation

/// Shared joint ordering for both hand-camera consumers. Never selects among multiple hands.
enum HandPoseExtractor {
    static func evidence(
        from hand: VNHumanHandPoseObservation,
        timestamp: Double,
        generation: UUID,
        width: Double,
        height: Double
    ) throws -> HandEvidence {
        let names: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]
        let points = try names.map { name in
            let p = try hand.recognizedPoint(name)
            return HandPoint(x: p.location.x, y: p.location.y, confidence: p.confidence)
        }
        let side: HandSide?
        switch hand.chirality {
        case .left: side = .left
        case .right: side = .right
        default: side = nil
        }
        return HandEvidence(
            timestamp: timestamp, generation: generation,
            width: width,
            height: height, side: side, points: points
        )
    }
}
