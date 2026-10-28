//
//  SessionStageSurface.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

/// Full-screen guidance leaves the live camera mounted beneath its presentation.
struct SessionStageSurface<Content: View, Controls: View>: View {
    let background: Color
    let border: Color
    @ViewBuilder var content: () -> Content
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(spacing: 24) {
            content()
            controls()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(border, lineWidth: 8)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
