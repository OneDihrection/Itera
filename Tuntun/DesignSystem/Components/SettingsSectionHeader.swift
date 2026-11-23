//
//  SettingsSectionHeader.swift
//  Tuntun
//
//  Created by dimaswisodewo on 23/11/2026.
//

import SwiftUI

/// A Preferences section header: a yellow `brand` icon tile beside a bold title, with an
/// optional trailing action. Replaces the system's grey uppercase `Form` header.
struct TMSettingsSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let trailing: Trailing

    init(
        title: LocalizedStringKey,
        symbol: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            iconTile

            Text(title)
                .typography(.title3, weight: .bold)
                .foregroundStyle(TherapyPalette.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            trailing
        }
        .textCase(nil)
        .frame(minHeight: 44)
        .padding(.bottom, 4)
    }

    private var iconTile: some View {
        Image(systemName: symbol)
            .typography(size: 16, weight: .semiBold, relativeTo: .title3)
            .foregroundStyle(TherapyPalette.onBrand)
            .frame(width: 32, height: 32)
            .background(
                TherapyPalette.brand,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
