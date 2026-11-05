//
//  TherapyFruitHarvest.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 04/11/2026.
//

import SwiftUI

/// Mango and woven shoulder bag artwork driven exclusively by supplied accepted exercise state.
///
/// The mango travels with the hand toward the bag at the opposite shoulder. Once the
/// caller reports the target as delivered, the mango drops into the bag and the hand
/// returns empty. It owns no balance geometry, exercise timing, rewards or navigation.
struct TherapyFruitHarvest: View {
    let handPosition: CGPoint
    let bagPosition: CGPoint
    let holdProgress: Double
    let delivered: Bool
    let waiting: Bool
    let collected: Int
    let showsMango: Bool
    let showsBag: Bool
    let animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastHandPosition: CGPoint?
    @State private var dropPosition: CGPoint?
    @State private var wasDelivered = false

    private var moves: Bool { animated && !reduceMotion && scenePhase == .active }

    var body: some View {
        ZStack {
            if showsBag {
                bag
                    .position(bagPosition)
                    .animation(moves && !waiting ? .easeOut(duration: 0.25) : nil, value: bagPosition)
            }

            if let dropPosition {
                mangoImage(size: 58)
                    .position(dropPosition)
            }

            if showsMango {
                mango
                    .position(handPosition)
                    .animation(waiting || !moves ? nil : .linear(duration: 0.10), value: handPosition)
            }
        }
        .onChange(of: handPosition, initial: true) { _, position in
            if showsMango && !waiting {
                lastHandPosition = position
            }
        }
        .task(id: "\(delivered)-\(waiting)-\(scenePhase == .active)") {
            await presentDrop()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Drops the carried mango into the bag once per delivery. Pause/background cancels
    /// the decorative flight, never exercise state.
    private func presentDrop() async {
        dropPosition = nil
        let previouslyDelivered = wasDelivered
        wasDelivered = delivered

        guard delivered, !previouslyDelivered, !waiting, moves,
              let origin = lastHandPosition else {
            return
        }

        dropPosition = origin
        do {
            try await Task.sleep(for: .milliseconds(25))
            withAnimation(.easeIn(duration: 0.55)) {
                dropPosition = CGPoint(x: bagPosition.x, y: bagPosition.y - 24)
            }
            try await Task.sleep(for: .milliseconds(600))
        } catch {
            // Cancelled with the view or the pause state; nothing to restore.
        }
        dropPosition = nil
    }

    private var mango: some View {
        ZStack {
            Circle()
                .fill(Self.glow.opacity(0.15 + holdProgress * 0.45))
                .frame(width: 104, height: 104)
                .blur(radius: 10)
            mangoImage(size: 80)
                .scaleEffect(1 - holdProgress * 0.12)
            if waiting {
                Image(systemName: "pause.circle.fill")
                    .typography(.headline)
                    .foregroundStyle(.white, TherapyPalette.ink)
                    .offset(x: -32, y: -28)
            }
        }
        .opacity(waiting ? 0.65 : 1)
    }

    private var bag: some View {
        let inside = min(3, collected + (delivered ? 1 : 0))

        return VStack(spacing: 2) {
            ZStack(alignment: .top) {
                // Mangoes peek out above the woven band.
                HStack(spacing: -14) {
                    ForEach(0..<inside, id: \.self) { _ in
                        mangoImage(size: 38)
                    }
                }
                .offset(y: 22)
                Image("kampung-tas")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                if delivered && !waiting {
                    Image(systemName: "checkmark.circle.fill")
                        .typography(.headline)
                        .foregroundStyle(.white, TherapyPalette.green)
                        .offset(x: 40, y: 36)
                }
            }
            .frame(width: 110, height: 104)
            Text("balance.fruit.count \(Int64(collected))")
                .typography(.footnote)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(TherapyPalette.ink.opacity(0.85), in: Capsule())
        }
        .opacity(waiting ? 0.65 : 1)
        .animation(waiting || !moves ? nil : .easeOut(duration: 0.3), value: inside)
    }

    private func mangoImage(size: CGFloat) -> some View {
        Image("kampung-mangga")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private static let glow = Color(red: 0.98, green: 0.78, blue: 0.35)
}
