//
//  TherapyLoadingOverlay.swift
//  Tuntun
//
//  Created by dimaswisodewo on 20/11/2026.
//

import SwiftUI

/// The frosted, darkened backdrop shared by the full-screen countdown and the loading overlay.
struct TMFrostedBackdrop: View {
    /// How much the frost is darkened; a floating panel passes a lighter value.
    var dimming = 0.5

    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(Color.black.opacity(dimming))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// A spinner and one short message over the frosted backdrop, shown while a session starts or
/// winds down. It takes every tap so nothing is triggered twice during the wait.
struct TMLoadingOverlay: View {
    let message: LocalizedStringKey

    /// Starting and ending a session does synchronous main-actor work (audio clips, listening,
    /// teardown). A caller raises its loading flag, sleeps this long so the overlay is drawn
    /// first (about three frames at 60 Hz), and only then starts that work.
    static let presentationDelay: Duration = .milliseconds(50)

    var body: some View {
        ZStack {
            // Under the backdrop: compiles the rest shaders while the session prepares.
            TMShaderWarmUp()

            TMFrostedBackdrop()

            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .tint(.white)

                Text(message)
                    .typography(size: 32, weight: .bold, relativeTo: .title)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .foregroundStyle(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(message))
        }
        .contentShape(Rectangle())
        .onTapGesture {}
        .transition(.opacity)
    }
}

#Preview {
    Color.gray
        .overlay {
            TMLoadingOverlay(message: "loading.preparingSession")
        }
}
