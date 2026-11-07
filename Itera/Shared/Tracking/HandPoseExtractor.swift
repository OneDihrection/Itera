//
//  HandPoseExtractor.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Vision
import Foundation

/// Shared joint ordering and selection inputs for both hand-camera consumers.
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

    /// Selection inputs for one detected hand: aspect-corrected wrist, hand size and chirality.
    static func candidate(
        for hand: VNHumanHandPoseObservation,
        aspect: Double
    ) -> HandSubjectSelector.Candidate {
        let wrist = try? hand.recognizedPoint(.wrist)
        let knuckle = try? hand.recognizedPoint(.middleMCP)

        func position(_ point: VNRecognizedPoint?) -> TherapyPoint? {
            guard let point, point.confidence >= 0.3 else {
                return nil
            }

            return TherapyPoint(x: point.location.x * aspect, y: point.location.y)
        }

        let wristPosition = position(wrist)
        let knucklePosition = position(knuckle)
        var size = 0.0

        if let wristPosition, let knucklePosition {
            size = (wristPosition - knucklePosition).length
        }

        let side: HandSide?
        switch hand.chirality {
        case .left:
            side = .left
        case .right:
            side = .right
        default:
            side = nil
        }

        return HandSubjectSelector.Candidate(
            // An unreadable wrist sits far away, so continuity can never select it.
            wrist: wristPosition ?? TherapyPoint(x: .infinity, y: .infinity),
            size: size,
            side: side
        )
    }
}
