//
//  BalanceFruitOverlay.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 04/11/2026.
//

import SwiftUI

/// Uses the same aspect-fit and mirroring transform as the balance target overlay.
///
/// The woven bag hangs just outside the target (opposite) shoulder, so the target
/// circle and its countdown stay visible. The mango rides above the moving hand.
struct BalanceFruitOverlay: View {
    let snapshot: BalanceSnapshot
    let mirrored: Bool
    let waiting: Bool
    @AppStorage(PracticePreferences.calmMode) private var calmMode = false

    var body: some View {
        GeometryReader { geometry in
            if let overlay = snapshot.overlay {
                let size = geometry.size
                let delivered = snapshot.phase == .returning
                let targetShoulder = snapshot.activeArm == .left ? overlay.rightShoulder : overlay.leftShoulder
                let ownShoulder = snapshot.activeArm == .left ? overlay.leftShoulder : overlay.rightShoulder
                let shoulder = screenPoint(targetShoulder, aspect: overlay.aspect, size: size)
                let other = screenPoint(ownShoulder, aspect: overlay.aspect, size: size)
                let outward: CGFloat = shoulder.x >= other.x ? 1 : -1
                let bag = clamp(
                    CGPoint(x: shoulder.x + outward * 100, y: shoulder.y + 60),
                    size: size,
                    margin: 64
                )
                let hand = overlay.wrist.map { (wrist: TherapyPoint) -> CGPoint in
                    let point = screenPoint(wrist, aspect: overlay.aspect, size: size)
                    return clamp(CGPoint(x: point.x, y: point.y - 64), size: size, margin: 48)
                } ?? CGPoint(x: size.width / 2, y: size.height / 2)

                TherapyFruitHarvest(
                    handPosition: hand,
                    bagPosition: bag,
                    holdProgress: snapshot.phase == .holding ? overlay.targetProgress : 0,
                    delivered: delivered,
                    waiting: waiting,
                    collected: snapshot.deliveredFruit,
                    showsMango: overlay.wrist != nil && [.reaching, .holding].contains(snapshot.phase),
                    showsBag: [.reaching, .holding, .returning].contains(snapshot.phase),
                    animated: !calmMode
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func screenPoint(_ source: TherapyPoint, aspect: Double, size: CGSize) -> CGPoint {
        let scale = min(size.width / aspect, size.height)
        let offsetX = (size.width - aspect * scale) / 2
        let offsetY = (size.height - scale) / 2
        return CGPoint(
            x: offsetX + (mirrored ? aspect - source.x : source.x) * scale,
            y: offsetY + (1 - source.y) * scale
        )
    }

    private func clamp(_ point: CGPoint, size: CGSize, margin: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(margin, size.width - margin), max(margin, point.x)),
            y: min(max(margin, size.height - margin - 40), max(margin, point.y))
        )
    }
}
