//
//  TherapyIntroCards.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 23/11/2026.
//

import SwiftUI

// The soft grey tiles on an exercise intro: the target figures ("3 set", "8 repetisi") and the
// short notes under them. They take values only; the caller decides what to show.

// MARK: - Stat tile

/// One target figure on a soft rounded tile: a big bold value over a muted unit.
/// Tiles placed side by side in an `HStack` share the width equally.
struct TMTherapyStatTile: View {
    let value: Text
    let unit: Text
    var fill: Color = TherapyPalette.canvas

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            value
                .typography(size: 52, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(TherapyPalette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            unit
                .typography(size: 24, weight: .regular, relativeTo: .title3)
                .foregroundStyle(TherapyPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Info card

/// A short note on a soft rounded card: a tinted icon beside a bold line and a regular line.
/// The message may use Markdown emphasis from the String Catalog, such as **Stop**.
struct TMTherapyInfoCard: View {
    let symbol: String
    let tint: Color
    let title: Text
    let message: Text
    var fill: Color = TherapyPalette.canvas

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .typography(size: 24, weight: .medium, relativeTo: .title3)
                .foregroundStyle(tint)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                title
                    .typography(size: 21, weight: .bold, relativeTo: .headline)

                message
                    .typography(size: 20, weight: .regular, relativeTo: .body)
            }
            .foregroundStyle(TherapyPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Intro cards") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            TMTherapyStatTile(value: Text(verbatim: "3"), unit: Text(verbatim: "set"))
            TMTherapyStatTile(value: Text(verbatim: "8"), unit: Text(verbatim: "repetisi"))
            TMTherapyStatTile(value: Text(verbatim: "10–15"), unit: Text(verbatim: "menit"))
        }

        TMTherapyInfoCard(
            symbol: "info.circle",
            tint: TherapyPalette.warning,
            title: Text(verbatim: "Bergerak sesuai kemampuan."),
            message: Text(verbatim: "Berhenti jika terasa nyeri.")
        )
    }
    .padding(40)
}
#endif
