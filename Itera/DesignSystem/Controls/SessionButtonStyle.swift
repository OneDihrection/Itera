//
//  SessionButtonStyle.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct SessionButtonStyle: ButtonStyle {
    var tint: Color = Color(white: 0.16)
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typography(compact ? .custom(size: 24, weight: .bold, relativeTo: .title2) : .therapyControl)
            .padding(.horizontal, 24)
            .frame(minHeight: compact ? 44 : 72)
            .background(
                tint.opacity(configuration.isPressed ? 0.55 : 0.85),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(.white)
    }
}
