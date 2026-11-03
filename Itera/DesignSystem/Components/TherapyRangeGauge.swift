//
//  TherapyRangeGauge.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import SwiftUI

/// A measured movement range split into a start zone and a target zone, with labels at each end.
/// It accepts only values and labels; callers decide what the range means.
struct TherapyRangeGauge: View {
    let startLabel: LocalizedStringKey
    let endLabel: LocalizedStringKey
    /// Fraction of the range, from the start end, that counts as back at the start.
    var startZone = 0.25
    /// Fraction of the range, from the start end, where the target zone begins.
    var targetStart = 0.8

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    TherapyPalette.warning
                        .frame(width: geometry.size.width * startZone)
                    TherapyPalette.subtleSurface
                    TherapyPalette.green
                        .frame(width: geometry.size.width * (1 - targetStart))
                }
                .clipShape(Capsule())
            }
            .frame(height: 28)
            HStack {
                Text(startLabel)
                Spacer()
                Text(endLabel)
            }
            .typography(.footnote)
            .foregroundStyle(TherapyPalette.muted)
        }
        .accessibilityElement(children: .combine)
    }
}
