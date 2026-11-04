//
//  TherapyFruitHarvest.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 04/11/2026.
//

import SwiftUI

/// Decorative artwork driven exclusively by supplied accepted exercise state.
struct TherapyFruitHarvest: View {
    let fruitPosition: CGPoint
    let basketPosition: CGPoint
    let ripeness: Double
    let carrying: Bool
    let waiting: Bool
    let collected: Int
    let showsFruit: Bool
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastCarriedPosition: CGPoint?
    @State private var lastDeposit: Int?
    @State private var depositPosition: CGPoint?

    var body: some View {
        ZStack {
            basket
                .position(basketPosition)

            if let depositPosition {
                Image("balance-apple")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .position(depositPosition)
            }

            if showsFruit {
                apple
                    .position(fruitPosition)
                    .animation(waiting || reduceMotion || !animated ? nil : .linear(duration: 0.10), value: fruitPosition)
            }
        }
        .onChange(of: fruitPosition, initial: true) { _, position in
            if carrying && !waiting {
                lastCarriedPosition = position
            }
        }
        .task(id: "\(collected)-\(waiting)-\(scenePhase == .active)") {
            depositPosition = nil
            guard let previous = lastDeposit else {
                lastDeposit = collected
                return
            }
            lastDeposit = collected
            guard collected > previous, !waiting, !reduceMotion, animated, scenePhase == .active,
                  let origin = lastCarriedPosition else {
                return
            }
            depositPosition = origin
            do {
                try await Task.sleep(for: .milliseconds(25))
                withAnimation(.easeInOut(duration: 0.65)) {
                    depositPosition = basketPosition
                }
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                // Pause/background cancels decorative flight, never exercise state.
            }
            depositPosition = nil
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var apple: some View {
        ZStack {
            Circle()
                .fill(TherapyPalette.peach.opacity(0.15 + ripeness * 0.35))
                .frame(width: 100, height: 100)
                .blur(radius: 10)
            Image("balance-apple")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .saturation(carrying ? 1 : 0.25 + ripeness * 0.75)
                .scaleEffect(carrying ? 1 : 0.85 + ripeness * 0.15)
            if carrying {
                Image(systemName: "checkmark.circle.fill")
                    .typography(.headline)
                    .foregroundStyle(.white, TherapyPalette.green)
                    .offset(x: 32, y: 28)
            }
            if waiting {
                Image(systemName: "pause.circle.fill")
                    .typography(.headline)
                    .foregroundStyle(.white, TherapyPalette.ink)
                    .offset(x: -32, y: -28)
            }
        }
        .opacity(waiting ? 0.65 : 1)
    }

    private var basket: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                HStack(spacing: -16) {
                    ForEach(0..<min(5, max(0, collected)), id: \.self) { _ in
                        Image("balance-apple")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .offset(y: -28)
                Image(systemName: "basket.fill")
                    .typography(size: 68, weight: .bold)
                    .foregroundStyle(TherapyPalette.peach)
                    .shadow(color: .black.opacity(0.35), radius: 2)
            }
            .frame(height: 80)
            Text("balance.fruit.count \(Int64(collected))")
                .typography(.footnote)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(TherapyPalette.ink.opacity(0.85), in: Capsule())
        }
        .animation(waiting || reduceMotion || !animated ? nil : .easeOut(duration: 0.3), value: collected)
    }
}
