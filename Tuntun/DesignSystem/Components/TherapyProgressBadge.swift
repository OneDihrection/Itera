//
//  TherapyProgressBadge.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

import SwiftUI

/// The yellow progress badge: a blue ribbon fanning out behind a white disc that carries a
/// number, with a small yellow dot at the disc's foot. `TMProgressHeaderCard` shows the week's
/// practice count on it and `TMHistoryCard` an exercise's position in the day.
///
/// It is decoration: the number is hidden from VoiceOver, so the caller's label must say it.
struct TMProgressBadge: View {
    let number: Int
    /// The badge is about 2.8 times as wide as it is tall, as in the design.
    var height: CGFloat = 108

    private var width: CGFloat {
        height * 2.8
    }

    var body: some View {
        ZStack {
            TherapyPalette.brand

            ribbon

            disc
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.12, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Parts

    /// Two tones: the outer fan and a lighter inner fold, both narrowing to the disc's foot.
    private var ribbon: some View {
        ZStack {
            TMProgressBadgeRibbon(inset: 0)
                .fill(TherapyPalette.badgeRibbon)

            TMProgressBadgeRibbon(inset: 0.22)
                .fill(TherapyPalette.badgeRibbonLight)
        }
    }

    /// The white disc rises past the badge's top edge, which clips it, as in the design.
    private var disc: some View {
        let diameter = height * 0.98

        return ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: diameter, height: diameter)

            Text(verbatim: "\(number)")
                .typography(
                    size: height * 0.72,
                    weight: .extraBold,
                    relativeTo: .largeTitle
                )
                .foregroundStyle(TherapyPalette.brand)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: diameter * 0.86)
                .dynamicTypeSize(.large)

            footDot(diameter: diameter)
        }
        .offset(y: -height * 0.12)
    }

    private func footDot(diameter: CGFloat) -> some View {
        let dot = height * 0.13

        return Circle()
            .fill(TherapyPalette.brand)
            .overlay {
                Circle()
                    .strokeBorder(Color.white, lineWidth: dot * 0.22)
            }
            .frame(width: dot, height: dot)
            .offset(y: diameter / 2 - dot * 0.2)
    }
}

/// A five-sided fan: wide along the top, sloping down both sides and meeting below the centre.
/// `inset` (0–0.4) narrows it toward the middle for the lighter inner fold.
private struct TMProgressBadgeRibbon: Shape {
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = rect.width * inset * 0.5

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: CGPoint(x: point(0.06, 0.72).x + side, y: point(0, 0.72).y))
        path.addLine(to: CGPoint(x: point(0.24, 0).x + side, y: rect.minY))
        path.addLine(to: CGPoint(x: point(0.76, 0).x - side, y: rect.minY))
        path.addLine(to: CGPoint(x: point(0.94, 0.72).x - side, y: point(0, 0.72).y))
        path.addLine(to: point(0.5, 0.96))
        path.closeSubpath()

        return path
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Progress badge") {
    VStack(spacing: 24) {
        TMProgressBadge(number: 3)
        TMProgressBadge(number: 12, height: 74)
    }
    .padding()
}
#endif
