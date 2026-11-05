//
//  FingerCameraGardenOverlay.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 03/11/2026.
//

import SwiftUI

/// Maps mirrored hand anchors into the persistent aspect-fit camera viewport.
///
/// Solid kampung artwork sits beside the hand rather than on it, so the patient can
/// still see their own fingers. Only the small melati stays at the pinch point.
struct FingerCameraGardenOverlay: View {
    let model: FingerSessionViewModel
    let animated: Bool
    @State private var parkedAnchor: CGPoint?
    @State private var parkedPose: Double?
    @State private var parkedSecured: Bool?

    var body: some View {
        GeometryReader { geometry in
            let style = model.gardenStyle
            let size = objectSize(style, viewport: geometry.size)
            let layout = CameraGardenLayout(evidence: model.lastGuideEvidence, viewport: geometry.size)
            let source = layout.anchor(style: style, finger: model.activity.finger, size: size)
            let waiting = !model.gardenAvailable
            let parked = layout.clamp(
                CGPoint(x: source.x + (source.x < geometry.size.width / 2 ? -40 : 40), y: source.y - 30),
                size: size
            )

            TherapyCameraGardenObject(
                style: style,
                anchor: waiting ? (parkedAnchor ?? parked) : source,
                collection: layout.collection,
                depositOrigin: layout.anchor(style: style, finger: model.gardenDepositFinger, size: size),
                pose: waiting ? (parkedPose ?? model.gardenPose) : model.gardenPose,
                secured: waiting ? (parkedSecured ?? model.gardenSecured) : model.gardenSecured,
                waiting: waiting,
                collected: model.gardenActivityCollectedCount,
                activeFinger: model.activity.finger,
                depositFinger: model.gardenDepositFinger,
                depositID: model.gardenDepositID,
                paused: model.paused,
                showsObject: model.activity.phase == .active,
                size: size,
                animated: animated
            )
            .onChange(of: model.gardenAvailable, initial: true) { _, available in
                parkedAnchor = available ? nil : parked
                parkedPose = available ? nil : model.gardenPose
                parkedSecured = available ? nil : model.gardenSecured
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func objectSize(_ style: GardenActivityStyle, viewport: CGSize) -> CGFloat {
        switch style {
        case .juice:
            return min(120, viewport.height * 0.26)
        case .well:
            return min(180, viewport.height * 0.38)
        case .garland:
            return 46
        case .bloom:
            return min(170, viewport.height * 0.36)
        case .chimes:
            return 0
        }
    }
}

private struct CameraGardenLayout {
    let evidence: HandEvidence?
    let viewport: CGSize

    /// Collections gather at the lower edge, away from the corner demonstration.
    var collection: CGPoint {
        CGPoint(x: max(viewport.width / 2, viewport.width - 150), y: max(40, viewport.height - 42))
    }

    var thumbtip: CGPoint { point(4) }

    func fingertip(_ finger: Int) -> CGPoint {
        point([8, 12, 16, 20][min(3, max(0, finger))])
    }

    func anchor(style: GardenActivityStyle, finger: Int, size: CGFloat) -> CGPoint {
        switch style {
        case .juice, .well, .bloom:
            return besideHand(size: size)
        case .garland:
            let tip = fingertip(finger)
            let pinch = CGPoint(x: (tip.x + thumbtip.x) / 2, y: (tip.y + thumbtip.y) / 2)
            // Slightly above the pinch so the touching fingertips stay visible.
            return clamp(CGPoint(x: pinch.x, y: pinch.y - 34), size: size)
        case .chimes:
            return collection
        }
    }

    /// Places artwork just outside the hand, preferring the side with free space.
    private func besideHand(size: CGFloat) -> CGPoint {
        var palm = CGPoint.zero
        for joint in [0, 5, 9, 13, 17] {
            let location = point(joint)
            palm.x += location.x / 5
            palm.y += location.y / 5
        }

        var minX = palm.x
        var maxX = palm.x
        for joint in [0, 4, 8, 12, 16, 20] {
            let x = point(joint).x
            minX = min(minX, x)
            maxX = max(maxX, x)
        }

        let gap = size / 2 + 24
        let right = maxX + gap
        let left = minX - gap
        let fitsRight = right + size / 2 < viewport.width - 24
        let fitsLeft = left - size / 2 > 24

        let x: CGFloat
        if fitsRight && (!fitsLeft || palm.x < viewport.width / 2) {
            x = right
        } else if fitsLeft {
            x = left
        } else {
            x = right
        }
        return clamp(CGPoint(x: x, y: palm.y - size * 0.15), size: size)
    }

    func clamp(_ point: CGPoint, size: CGFloat) -> CGPoint {
        let margin = max(30, size / 2 + 8)
        // Keep clear of the lower collection strip.
        let bottomReserve = max(margin, 130)
        var result = CGPoint(
            x: min(max(margin, viewport.width - margin), max(margin, point.x)),
            y: min(max(margin, viewport.height - bottomReserve), max(margin, point.y))
        )

        // Avoid the corner demonstration video.
        let demoWidth = min(220, viewport.width * 0.2)
        let demoHeight = min(170, viewport.height * 0.26)
        if result.x + size / 2 > viewport.width - demoWidth - 16 && result.y - size / 2 < demoHeight + 16 {
            result.x = max(margin, viewport.width - demoWidth - 24 - size / 2)
        }
        return result
    }

    private func point(_ joint: Int) -> CGPoint {
        guard let evidence, evidence.points.count == 21,
              evidence.width > 0, evidence.height > 0,
              evidence.points[joint].confidence >= 0.5 else {
            return CGPoint(x: viewport.width * 0.4, y: viewport.height * 0.45)
        }
        let scale = min(viewport.width / evidence.width, viewport.height / evidence.height)
        let width = evidence.width * scale
        let height = evidence.height * scale
        let point = evidence.points[joint]
        return CGPoint(
            x: (viewport.width - width) / 2 + (1 - point.x) * width,
            y: (viewport.height - height) / 2 + (1 - point.y) * height
        )
    }
}
