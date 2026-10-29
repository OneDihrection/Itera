//
//  TherapyArtwork.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TherapyArtwork: View {
    let name: String
    var mirrored = false

    var body: some View {
        (name.hasPrefix("symbol:") ? Image(systemName: String(name.dropFirst(7))) : Image(name))
            .resizable()
            .scaledToFit()
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }
}

struct TherapyArtworkPanel: View {
    let title: LocalizedStringKey
    let subtitle: String
    let artwork: String
    var mirrored = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .typography(size: 48, weight: .bold, relativeTo: .largeTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: subtitle)
                    .typography(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TherapyArtwork(name: artwork, mirrored: mirrored)
                .scaleEffect(1.25)
                .frame(
                    maxWidth: typeSize.isAccessibilitySize ? 240 : .infinity,
                    maxHeight: 280
                )
        }
        .padding(.leading, 28)
        .frame(minHeight: 260)
        .foregroundStyle(TherapyPalette.pastelInk)
        .background(TherapyPalette.hero)
        .clipped()
    }
}

struct TherapyExerciseRow: View {
    let title: LocalizedStringKey
    let subtitle: String
    let artwork: String
    let color: Color
    var mirrored = false
    var number: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                TherapyArtwork(name: artwork, mirrored: mirrored)
                    .scaleEffect(1.2)
                    .frame(width: 84, height: 84)
                    .background(color, in: RoundedRectangle(cornerRadius: 18))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).typography(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: subtitle).typography(.footnote)
                        .foregroundStyle(TherapyPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let number {
                    Text(verbatim: String(format: "%02d", number))
                        .typography(.title2)
                        .foregroundStyle(TherapyPalette.muted)
                        .accessibilityHidden(true)
                }
                Image(systemName: "play.circle")
                    .typography(size: 32, weight: .regular)
                    .foregroundStyle(TherapyPalette.green)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(TherapyPalette.ink)
            .padding(12)
            .background(TherapyPalette.surface, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(TherapySoundButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("exercise.previewHint")
    }
}
