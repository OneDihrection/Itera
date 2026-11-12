//
//  RepClipFrame.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import CoreGraphics
import Foundation

/// One low-resolution video frame, filtered as `RepClipPrivacy` asks before it is encoded, so
/// no picture is ever held without the censoring the caregiver chose.
struct RepClipFrame: Sendable {
    /// Monotonic capture time, in seconds, on the same clock as `TrackingObservation.timestamp`.
    let time: Double
    let jpeg: Data
}

/// What a clip hides. Chosen by the caregiver; either may be off, and with both off the clip is
/// a plain low-resolution video.
struct RepClipPrivacy: Sendable, Equatable {
    var blursFace = true
    var blursBackground = true
}

/// Head evidence for one detected person, in Vision's normalized image space (origin
/// bottom-left, unmirrored).
struct RepClipHead: Sendable {
    /// Confident nose, eye and ear points; empty when the face could not be located.
    let face: [CGPoint]
    let neck: CGPoint?
}
