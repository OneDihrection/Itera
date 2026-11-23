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

// MARK: - Tracking status chip

/// A white capsule in the camera's corner saying whether the patient is in position: a green
/// dot with "Posisi sudah pas" while tracking is good, a red one with "Posisi belum pas" while
/// it is not. The wording differs too, so the colour is never the only signal. The caller
/// decides what counts as positioned and when the chip shows.
struct TMTrackingStatusChip: View {
    let isPositioned: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        isPositioned ? TherapyPalette.success : TherapyPalette.warning
    }

    private var title: LocalizedStringKey {
        isPositioned ? "session.positionGood" : "session.positionPoor"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 12, height: 12)

            Text(title)
                .typography(size: 24, weight: .semiBold, relativeTo: .title3)
                .foregroundStyle(tint)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white, in: Capsule())
        // The chip is always white over the video, so its colours keep their light values.
        .environment(\.colorScheme, .light)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isPositioned)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Overlays `TMTrackingStatusChip` on a camera preview's top-left corner, inside the visible
    /// video when its bounds are known so it never sits in a letterbox margin. Nil hides it.
    func trackingStatusChip(_ isPositioned: Bool?, videoBounds: CGRect? = nil) -> some View {
        overlay(alignment: .topLeading) {
            if let isPositioned {
                TMTrackingStatusChip(isPositioned: isPositioned)
                    .padding(.leading, (videoBounds?.minX ?? 0) + 20)
                    .padding(.top, (videoBounds?.minY ?? 0) + 20)
                    .transition(.opacity)
            }
        }
    }
}

#Preview("Tracking status chip") {
    VStack(spacing: 24) {
        TMTrackingStatusChip(isPositioned: true)
        TMTrackingStatusChip(isPositioned: false)
    }
    .padding(40)
    .background(Color.gray)
}
