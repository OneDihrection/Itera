//
//  TherapyMusicMenu.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

struct TherapyMusicOption: Identifiable {
    let id: String
    let title: LocalizedStringKey
}

/// A native selection menu; playback and preferences remain with the caller.
struct TherapyMusicMenu: View {
    @Binding var selection: String
    let options: [TherapyMusicOption]
    var size: CGFloat = 64

    var body: some View {
        Menu {
            Picker("music.title", selection: $selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.id)
                }
            }
        } label: {
            Image(systemName: "music.note")
                .typography(.headline)
                .foregroundStyle(TherapyPalette.onHero)
                .frame(width: max(44, size), height: max(44, size))
                .background(TherapyPalette.action, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("music.change")
        .accessibilityValue(options.first(where: { $0.id == selection })?.title ?? "music.off")
    }
}
