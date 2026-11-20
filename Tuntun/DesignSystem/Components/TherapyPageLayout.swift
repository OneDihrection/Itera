//
//  TherapyPageLayout.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

// MARK: - Page header

/// A centered page title with an optional leading circle action (back or close).
/// Without a title the header keeps its height and shows only the action.
struct TMTherapyPageHeader: View {
    let title: LocalizedStringKey?
    var leadingTitle: LocalizedStringKey? = nil
    var leadingSymbol = "chevron.left"
    var leadingAction: (() -> Void)? = nil
    var trailingContentWidth: CGFloat = 0

    var body: some View {
        ZStack {
            if let title {
                Text(title)
                    .typography(size: 24, weight: .semiBold, relativeTo: .title2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, max(80, trailingContentWidth + 16))
                    .accessibilityAddTraits(.isHeader)
            }

            if let leadingAction, let leadingTitle {
                HStack {
                    TMTherapyIconButton(
                        title: leadingTitle,
                        symbol: leadingSymbol,
                        size: 44,
                        circle: true,
                        action: leadingAction
                    )
                    Spacer()
                }
            }
        }
        .foregroundStyle(TherapyPalette.ink)
        .frame(minHeight: 64)
    }
}

// MARK: - Media panel

/// A soft grey rounded panel that frames an illustration or demonstration,
/// with an optional heading such as "Animasi".
struct TMTherapyMediaPanel<Content: View>: View {
    var title: LocalizedStringKey? = nil
    var padding: CGFloat = 22
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .typography(size: 26, weight: .medium, relativeTo: .title3)
                    .foregroundStyle(TherapyPalette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.panel, in: RoundedRectangle(cornerRadius: 34))
    }
}
