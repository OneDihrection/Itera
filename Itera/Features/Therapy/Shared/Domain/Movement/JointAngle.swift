//
//  JointAngle.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import Foundation

enum JointAngle {
    /// The angle at `vertex` between the segments to `a` and `b`, in degrees (0...180).
    ///
    /// Points must share one aspect-corrected space. Returns nil when either segment is too short
    /// for a meaningful direction.
    static func degrees(
        at vertex: TherapyPoint,
        _ a: TherapyPoint,
        _ b: TherapyPoint
    ) -> Double? {
        let u = a - vertex
        let v = b - vertex
        let length = u.length * v.length

        guard length > 0.0001 else {
            return nil
        }

        let cosine = (u.x * v.x + u.y * v.y) / length
        return acos(max(-1, min(1, cosine))) * 180 / .pi
    }
}
