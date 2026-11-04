//
//  BalanceFruitOverlay.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 04/11/2026.
//

import SwiftUI

/// Uses the same aspect-fit and mirroring transform as the balance target overlay.
struct BalanceFruitOverlay: View {
    let snapshot: BalanceSnapshot
    let mirrored: Bool
    let waiting: Bool
    @AppStorage(PracticePreferences.calmMode) private var calmMode = false

    var body: some View {
        GeometryReader { geometry in
            if let overlay = snapshot.overlay {
                let carrying = snapshot.phase == .returning
                let anchor = carrying ? overlay.wrist : overlay.target
                let basket = CGPoint(x: geometry.size.width - 130, y: geometry.size.height - 75)
                let position = anchor.map { source in
                    fruitPoint(source, aspect: overlay.aspect, size: geometry.size)
                } ?? CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                TherapyFruitHarvest(
                    fruitPosition: position,
                    basketPosition: basket,
                    ripeness: carrying ? 1 : overlay.targetProgress,
                    carrying: carrying,
                    waiting: waiting,
                    collected: snapshot.deliveredFruit,
                    showsFruit: anchor != nil && [.reaching, .holding, .returning].contains(snapshot.phase),
                    animated: !calmMode
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fruitPoint(_ source: TherapyPoint, aspect: Double, size: CGSize) -> CGPoint {
        let scale = min(size.width / aspect, size.height)
        let offsetX = (size.width - aspect * scale) / 2
        let offsetY = (size.height - scale) / 2
        let x = offsetX + (mirrored ? aspect - source.x : source.x) * scale
        let y = offsetY + (1 - source.y) * scale
        // Keep the target/hand and its authoritative countdown unobstructed.
        return CGPoint(
            x: min(max(52, size.width - 52), max(52, x + 62)),
            y: min(max(52, size.height - 145), max(52, y - 65))
        )
    }
}
