//
//  TherapyArtwork.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMTherapyArtwork: View {
    let name: String
    var mirrored = false
    /// Shown instead when `name` is an asset the catalog does not contain, for artwork that
    /// is still being drawn. Accepts the same `symbol:` prefix.
    var fallback: String? = nil

    var body: some View {
        image(for: resolvedName)
            .resizable()
            .scaledToFit()
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }

    private var resolvedName: String {
        guard let fallback, !name.hasPrefix("symbol:"), UIImage(named: name) == nil else {
            return name
        }

        return fallback
    }

    private func image(for name: String) -> Image {
        name.hasPrefix("symbol:") ? Image(systemName: String(name.dropFirst(7))) : Image(name)
    }
}

/// Full-width exercise photography shared by plan and history card artwork slots.
/// The exercise title already provides its accessible description.
struct TMExerciseCardArtwork: View {
    let name: String

    var body: some View {
        TMTherapyArtwork(name: name)
            .frame(width: 300, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(TherapyPalette.outline, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
    }
}
