//
//  LanguageSelector.swift
//  Itera
//
//  Created by dimaswisodewo on 29/10/2026.
//

import SwiftUI

struct LanguageSelector: View {
    @Binding var language: String

    var body: some View {
        Picker("language.title", selection: $language) {
            Text("language.english").tag("en")
            Text("language.indonesian").tag("id")
        }
        .pickerStyle(.segmented)
        .typography(.body)
        .accessibilityLabel(Text("language.title"))
    }
}
