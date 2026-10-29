//
//  ExerciseIllustration.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct ExerciseIllustration: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .typography(size: 96, relativeTo: .largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .typography(.homeLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
