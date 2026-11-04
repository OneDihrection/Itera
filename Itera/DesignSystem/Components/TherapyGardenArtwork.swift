//
//  TherapyGardenArtwork.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 03/11/2026.
//

import SwiftUI

/// Visual themes only; exercise mapping and earned work belong to the caller.
enum GardenActivityStyle: Int, CaseIterable {
    case light, butterfly, seeds, petals, firefly
}

struct TherapyGardenFlower: View {
    var openness = 1.0
    var accent: Color = TherapyPalette.tertiary

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Capsule().fill(TherapyPalette.primary)
                    .frame(width: size * 0.035, height: size * 0.42)
                    .offset(y: size * 0.25)
                Ellipse().fill(TherapyPalette.primary.opacity(0.7))
                    .frame(width: size * 0.22, height: size * 0.08)
                    .rotationEffect(.degrees(-25)).offset(x: size * 0.09, y: size * 0.28)
                ForEach(0..<6) { petal in
                    Ellipse().fill(accent.gradient)
                        .frame(width: size * 0.24, height: size * 0.36)
                        .offset(y: -size * 0.18)
                        .rotationEffect(.degrees(Double(petal) * 60))
                        .scaleEffect(0.25 + 0.75 * max(0, min(1, openness)))
                }
                Circle().fill(TherapyPalette.primary.gradient)
                    .frame(width: size * 0.19, height: size * 0.19)
                Circle().fill(TherapyPalette.surface.opacity(0.6))
                    .frame(width: size * 0.045, height: size * 0.045)
                    .offset(x: -size * 0.03, y: -size * 0.03)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}

struct TherapyGardenBed: View {
    let title: LocalizedStringKey
    let flowers: Int
    let hasSeed: Bool
    let variation: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 24).fill(TherapyPalette.secondary)
                Ellipse().fill(TherapyPalette.primary.opacity(0.1))
                    .frame(height: 38).padding(.horizontal, 12)
                if flowers > 0 {
                    HStack(alignment: .bottom, spacing: -12) {
                        ForEach(0..<min(flowers, 3), id: \.self) { index in
                            TherapyGardenFlower(
                                openness: 1,
                                accent: (variation + index).isMultiple(of: 2) ? TherapyPalette.tertiary : TherapyPalette.surface
                            )
                            .frame(width: 92, height: index == 1 ? 144 : 120)
                        }
                    }
                    .padding(.bottom, 8)
                } else {
                    Image(systemName: hasSeed ? "leaf.fill" : "leaf")
                        .typography(size: 48, weight: .bold)
                        .foregroundStyle(TherapyPalette.primary.opacity(hasSeed ? 1 : 0.4))
                        .padding(.bottom, 36)
                }
            }
            .frame(height: 164)
            .accessibilityHidden(true)
            Text(title).typography(.headline).multilineTextAlignment(.center)
            Text("garden.flowerCount \(flowers)").typography(.body)
                .foregroundStyle(TherapyPalette.primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
