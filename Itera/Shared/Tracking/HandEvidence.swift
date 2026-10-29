//
//  HandEvidence.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

enum HandSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
}

struct HandPoint: Equatable {
    let x: Double
    let y: Double
    let confidence: Float
}

/// Unmirrored image coordinates. Joint order is wrist, then four joints per finger.
struct HandEvidence {
    let timestamp: TimeInterval
    let generation: UUID
    let width: Double
    let height: Double
    let side: HandSide?
    let points: [HandPoint]

    func distance(_ a: Int, _ b: Int) -> Double {
        hypot((points[a].x - points[b].x) * width / height, points[a].y - points[b].y)
    }

    func angle(_ a: Int, _ b: Int, _ c: Int) -> Double {
        let u = ((points[a].x - points[b].x) * width / height, points[a].y - points[b].y)
        let v = ((points[c].x - points[b].x) * width / height, points[c].y - points[b].y)
        let length = hypot(u.0, u.1) * hypot(v.0, v.1)
        guard length > 0.0001 else {
            return .nan
        }
        return acos(max(-1, min(1, (u.0 * v.0 + u.1 * v.1) / length))) * 180 / .pi
    }

}
