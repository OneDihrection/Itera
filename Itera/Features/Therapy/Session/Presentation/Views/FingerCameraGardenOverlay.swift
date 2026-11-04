//
//  FingerCameraGardenOverlay.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 03/11/2026.
//

import SwiftUI

/// Maps mirrored hand anchors into the persistent aspect-fit camera viewport.
struct FingerCameraGardenOverlay: View {
    let model: FingerSessionViewModel
    let animated: Bool
    @State private var parkedAnchor: CGPoint?
    @State private var parkedPose: Double?
    @State private var parkedSecured: Bool?

    var body: some View {
        GeometryReader { geometry in
            let layout = CameraGardenLayout(evidence: model.lastGuideEvidence, viewport: geometry.size)
            let tether = model.gardenStyle == .butterfly
                ? layout.anchor(style: .light, finger: model.activity.finger)
                : layout.fingertip(model.activity.finger)
            let source = layout.anchor(style: model.gardenStyle, finger: model.activity.finger)
            let waiting = !model.gardenAvailable
            let parked = layout.clamp(CGPoint(x: source.x + (source.x < geometry.size.width / 2 ? -65 : 65), y: source.y - 50))
            TherapyCameraGardenObject(
                style: model.gardenStyle,
                anchor: waiting ? (parkedAnchor ?? parked) : source,
                tether: tether,
                planter: layout.planter,
                depositOrigin: layout.anchor(style: model.gardenStyle, finger: model.gardenDepositFinger),
                pose: waiting ? (parkedPose ?? model.gardenPose) : model.gardenPose,
                secured: waiting ? (parkedSecured ?? model.gardenSecured) : model.gardenSecured,
                waiting: waiting,
                collected: [.hookFist, .opposition].contains(model.activity.kind)
                    ? model.gardenActivityCollectedCount : model.gardenCollectedCount,
                depositID: model.gardenDepositID,
                paused: model.paused,
                showsObject: model.activity.phase == .active,
                size: model.gardenStyle == .petals ? min(280, geometry.size.height * 0.5) : 94,
                animated: animated,
                secondTether: model.gardenStyle == .seeds ? layout.thumbtip : nil
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
}

private struct CameraGardenLayout {
    let evidence: HandEvidence?
    let viewport: CGSize

    var planter: CGPoint {
        CGPoint(x: max(viewport.width / 2, viewport.width - 155), y: max(40, viewport.height - 42))
    }

    var thumbtip: CGPoint { point(4) }

    func fingertip(_ finger: Int) -> CGPoint {
        point([8, 12, 16, 20][min(3, max(0, finger))])
    }

    func anchor(style: GardenActivityStyle, finger: Int) -> CGPoint {
        var palm = CGPoint.zero
        for joint in [0, 5, 9, 13, 17] {
            let location = point(joint)
            palm.x += location.x / 5
            palm.y += location.y / 5
        }
        switch style {
        case .light:
            return clamp(palm)
        case .butterfly:
            var minX = palm.x
            var maxX = palm.x
            for joint in [0, 4, 8, 12, 16, 20] {
                let x = point(joint).x
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            let right = maxX + 65
            let left = minX - 65
            return clamp(CGPoint(x: right < viewport.width - 260 ? right : left, y: palm.y - 70))
        case .petals:
            return clamp(CGPoint(x: palm.x, y: palm.y - 60))
        case .seeds:
            let tip = fingertip(finger)
            return clampSeed(CGPoint(x: (tip.x + thumbtip.x) / 2, y: (tip.y + thumbtip.y) / 2))
        case .firefly:
            let joint = [8, 12, 16, 20][min(3, max(0, finger))]
            let tip = point(joint)
            let previous = point(joint - 1)
            let dx = tip.x - previous.x
            let dy = tip.y - previous.y
            let length = max(1, hypot(dx, dy))
            return clamp(CGPoint(x: tip.x + dx / length * 65, y: tip.y + dy / length * 65))
        }
    }

    private func clampSeed(_ point: CGPoint) -> CGPoint {
        // A tiny seed stays between the selected pair, rather than being displaced by demo avoidance.
        CGPoint(
            x: min(max(18, viewport.width - 18), max(18, point.x)),
            y: min(max(22, viewport.height - 22), max(22, point.y))
        )
    }

    func clamp(_ point: CGPoint) -> CGPoint {
        var result = CGPoint(
            x: min(max(60, viewport.width - 60), max(60, point.x)),
            y: min(max(60, viewport.height - 110), max(60, point.y))
        )
        let demoWidth = min(220, viewport.width * 0.2)
        let demoHeight = min(170, viewport.height * 0.26)
        if result.x > viewport.width - demoWidth - 65 && result.y < demoHeight + 65 {
            result.x = max(60, viewport.width - demoWidth - 75)
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
        return CGPoint(x: (viewport.width - width) / 2 + (1 - point.x) * width,
                       y: (viewport.height - height) / 2 + (1 - point.y) * height)
    }
}
