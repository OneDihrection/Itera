//
//  TherapyHistoryCard.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

import SwiftUI

/// One exercise on a day's progress page: its name on the left and the numbered progress badge
/// on the right, on a pale blue card.
///
/// With an action the card is a button (for example to open that exercise's report); without
/// one it is plain text. It takes values only.
struct TMHistoryCard: View {
    let title: LocalizedStringKey
    /// The exercise's position in the day, shown on the badge.
    let number: Int
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                card
            }
            .buttonStyle(TMTherapySoundButtonStyle())
            .accessibilityHint("historyCard.hint")
        } else {
            card
        }
    }

    private var card: some View {
        HStack(spacing: 32) {
            Text(title)
                // Same size as the day page's title (26 pt), one weight heavier than medium.
                .typography(size: 26, weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            TMProgressBadge(number: number, height: 100)
        }
        .padding(.leading, 36)
        .padding(.trailing, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TherapyPalette.historyCard,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("historyCard.position \(number)") + Text(verbatim: ", ") + Text(title))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("History card") {
    VStack(spacing: 16) {
        TMHistoryCard(title: "exercise.opposition", number: 1) {}
        TMHistoryCard(title: "session.armRaise", number: 2)
    }
    .padding(32)
}
#endif
