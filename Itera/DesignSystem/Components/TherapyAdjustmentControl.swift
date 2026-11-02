//
//  TherapyAdjustmentControl.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

/// A large, explicit value control for settings where both directions must remain easy to target.
struct TherapyAdjustmentControl: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var suffix: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .typography(.body)

            HStack(spacing: 14) {
                adjustmentButton(
                    title: "action.decrease",
                    symbol: "minus",
                    disabled: value <= range.lowerBound
                ) {
                    value = max(range.lowerBound, value - step)
                }

                VStack(spacing: 2) {
                    Text(verbatim: String(value))
                        .typography(.title)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let suffix {
                        Text(suffix)
                            .typography(.footnote)
                            .foregroundStyle(TherapyPalette.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                adjustmentButton(
                    title: "action.increase",
                    symbol: "plus",
                    disabled: value >= range.upperBound
                ) {
                    value = min(range.upperBound, value + step)
                }
            }
        }
        .padding(18)
        .background(TherapyPalette.cream, in: RoundedRectangle(cornerRadius: 22))
    }

    private func adjustmentButton(
        title: LocalizedStringKey,
        symbol: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .typography(size: 28, weight: .bold)
                .foregroundStyle(TherapyPalette.green)
                .frame(width: 76, height: 68)
                .background(TherapyPalette.mint, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(TherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: String(value)))
    }
}
