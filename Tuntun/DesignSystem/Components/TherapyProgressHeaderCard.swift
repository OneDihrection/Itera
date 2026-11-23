//
//  TherapyProgressHeaderCard.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

import SwiftUI

/// The Progress page's opening card: a small caption, an encouraging headline and the progress
/// badge with a number on the right. It is information only: it takes no taps.
///
/// It takes formatted text and the badge number; counting practice days stays with the caller.
struct TMProgressHeaderCard: View {
    let caption: LocalizedStringKey
    let headline: LocalizedStringKey
    let badgeNumber: Int

    var body: some View {
        TMTherapyCard(color: TherapyPalette.progressCanvas, outlined: true, padding: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 32) {
                    message
                    Spacer(minLength: 0)
                    TMProgressBadge(number: badgeNumber)
                }

                // Large text: the badge moves under the message instead of squeezing it.
                VStack(alignment: .leading, spacing: 20) {
                    message
                    TMProgressBadge(number: badgeNumber, height: 80)
                }
            }
        }
        // VoiceOver reads caption and headline as one element; the badge is decoration.
        .accessibilityElement(children: .combine)
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .typography(.body)
                .foregroundStyle(TherapyPalette.muted)

            Text(headline)
                .typography(size: 34, weight: .semiBold, relativeTo: .title)
                .foregroundStyle(TherapyPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Progress header card") {
    TMProgressHeaderCard(
        caption: "progress.header.caption",
        headline: "progress.header.headline \(3)",
        badgeNumber: 3
    )
    .padding(32)
    .background(TherapyPalette.progressCanvas)
}
#endif
