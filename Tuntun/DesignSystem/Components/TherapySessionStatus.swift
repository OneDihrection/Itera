//
//  TherapySessionStatus.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

// MARK: - Completion mark

/// A large circle with a check, for a finished set or session. Green with a white check by
/// default; the shared exercise screens pass `TherapyPalette.brand` and `TherapyPalette.onBrand`.
struct TMTherapyCompletionMark: View {
    var size: CGFloat = 128
    var tint: Color = TherapyPalette.success
    var checkColor: Color = .white

    var body: some View {
        Image(systemName: "checkmark")
            .typography(size: size * 0.42, weight: .bold)
            .foregroundStyle(checkColor)
            .frame(width: size, height: size)
            .background(tint, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Feedback pill

/// A short live cue drawn over the camera, such as "Bagus! Gerakan sudah sesuai".
struct TMTherapyFeedbackPill: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .typography(size: 26, weight: .medium, relativeTo: .title3)
            .foregroundStyle(TherapyPalette.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
