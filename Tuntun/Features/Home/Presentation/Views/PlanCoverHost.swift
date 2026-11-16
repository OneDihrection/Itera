//
//  PlanCoverHost.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// The full-screen cover that runs today's plan. It stays mounted while its page changes, so a
/// session, the rest and the next intro cross-fade instead of dismissing and presenting again.
struct TMPlanCoverHost<Builder: PlanCoverBuildable>: View {
    let route: PlanCoverRoute
    let builder: Builder

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedRoute: PlanCoverRoute?

    var body: some View {
        let shown = displayedRoute ?? route

        ZStack {
            TherapyPalette.canvas.ignoresSafeArea()

            builder.buildCoverPage(shown)
                .id(shown)
                .transition(.opacity)
        }
        .onChange(of: route, initial: true) { _, route in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                displayedRoute = route
            }
        }
    }
}

extension View {
    /// Re-applies the app-wide styling inside a sheet or cover; Mac Catalyst does not reliably
    /// forward the presenter's environment into presented content.
    func modalEnvironment(buttonFeedback: @escaping @MainActor () -> Void) -> some View {
        environment(\.buttonFeedback, buttonFeedback)
            .typography(.body)
            .buttonStyle(TMTherapySoundButtonStyle())
    }
}
