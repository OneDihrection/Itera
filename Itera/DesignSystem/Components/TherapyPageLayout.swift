//
//  TherapyPageLayout.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

// MARK: - Page header

/// A centered page title with an optional leading circle action (back or close).
struct TherapyPageHeader: View {
    let title: LocalizedStringKey
    var leadingTitle: LocalizedStringKey? = nil
    var leadingSymbol = "chevron.left"
    var leadingAction: (() -> Void)? = nil
    var trailingContentWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Text(title)
                .typography(size: 24, weight: .semiBold, relativeTo: .title2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, max(80, trailingContentWidth + 16))
                .accessibilityAddTraits(.isHeader)

            if let leadingAction, let leadingTitle {
                HStack {
                    TherapyIconButton(
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

// MARK: - Hero card

/// The black "today's exercise" card with a large circular action on the trailing side.
struct TherapyHeroCard: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    var actionSymbol = "play.fill"
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 24))

        layout {
            VStack(alignment: .leading, spacing: 18) {
                Text(eyebrow)
                    .typography(size: 30, weight: .regular, relativeTo: .title3)
                Text(title)
                    .typography(size: 64, weight: .bold, relativeTo: .largeTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .typography(size: 30, weight: .regular, relativeTo: .title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionButton
        }
        .foregroundStyle(TherapyPalette.onHero)
        .padding(.horizontal, 34)
        .padding(.vertical, 40)
        .background(TherapyPalette.heroCard, in: RoundedRectangle(cornerRadius: 30))
    }

    private var actionButton: some View {
        Button(action: action) {
            VStack(spacing: 22) {
                Image(systemName: actionSymbol)
                    .typography(size: 48, weight: .bold)
                    .foregroundStyle(TherapyPalette.heroCard)
                    // A play triangle looks centered only when nudged toward its point.
                    .offset(x: actionSymbol == "play.fill" ? 4 : 0)
                    .frame(width: 120, height: 120)
                    .background(TherapyPalette.onHero, in: Circle())
                Text(actionTitle)
                    .typography(size: 24, weight: .bold, relativeTo: .headline)
                    .multilineTextAlignment(.center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TherapySoundButtonStyle())
    }
}

// MARK: - Program card

/// A black list card with a white thumbnail tile, a title and a one-line detail.
struct TherapyProgramCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let artwork: String
    var mirrored = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                TherapyArtwork(name: artwork, mirrored: mirrored)
                    .foregroundStyle(Color.black)
                    .padding(14)
                    .frame(width: 100, height: 94)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .typography(size: 24, weight: .semiBold, relativeTo: .headline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .typography(size: 20, weight: .regular, relativeTo: .subheadline)
                        .multilineTextAlignment(.leading)
                        .opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(TherapyPalette.onHero)
            .padding(16)
            .background(TherapyPalette.heroCard, in: RoundedRectangle(cornerRadius: 30))
            .contentShape(RoundedRectangle(cornerRadius: 30))
        }
        .buttonStyle(TherapySoundButtonStyle())
    }
}

// MARK: - Media panel

/// A soft grey rounded panel that frames an illustration or demonstration,
/// with an optional heading such as "Animasi".
struct TherapyMediaPanel<Content: View>: View {
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
