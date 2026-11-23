//
//  HomeFloatingButton.swift
//  Tuntun
//
//  Created by Gracia A on 21/11/2026.
//

import SwiftUI

enum TMHomeFloatingButtonStyle: Equatable {
    case prominent
    case disabled
    case outlined
}

/// Beranda's bottom action and the soft fade that keeps it readable over scrolling cards.
struct TMHomeFloatingButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let style: TMHomeFloatingButtonStyle
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            Button(action: action) {
                HStack(spacing: 18) {
                    Image(systemName: symbol)
                    Text(title)
                }
                .typography(size: 36, weight: .semiBold, relativeTo: .title)
                .tracking(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 45)
                .frame(minHeight: 96)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay {
                    if style == .outlined {
                        Capsule()
                            .strokeBorder(TherapyPalette.planMutedInk, lineWidth: 2)
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(TMTherapySoundButtonStyle())
            .disabled(style == .disabled)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 188)
        .background {
            fade
                .allowsHitTesting(false)
        }
    }

    private var background: Color {
        switch style {
        case .prominent:
            return TherapyPalette.brand
        case .disabled:
            return TherapyPalette.actionMuted
        case .outlined:
            return TherapyPalette.canvas
        }
    }

    private var foreground: Color {
        switch style {
        case .prominent, .outlined:
            return TherapyPalette.onBrand
        case .disabled:
            return TherapyPalette.planMutedInk
        }
    }

    private var fade: some View {
        let mask = LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.52),
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        return Group {
            if reduceTransparency {
                TherapyPalette.canvas
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .mask(mask)
        .ignoresSafeArea(edges: .bottom)
    }
}
