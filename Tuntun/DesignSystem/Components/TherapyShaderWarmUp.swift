//
//  TherapyShaderWarmUp.swift
//  Tuntun
//
//  Created by dimaswisodewo on 23/11/2026.
//

import SwiftUI

/// Draws the rest pages' Metal shaders once, invisibly, so they are compiled before they are
/// needed.
///
/// SwiftUI builds a shader's pipeline the first time it is drawn, which stalled the move into the
/// first short or long rest of each launch. `Shader.compile(as:)` would do this without drawing,
/// but it needs iOS 18. Place it behind something opaque that is shown before a session, such as
/// `TMLoadingOverlay`; it ignores touches and accessibility.
struct TMShaderWarmUp: View {
    var body: some View {
        ZStack {
            TMTherapyBreathingCircle(intensity: 0.25, paused: true)
            TMTherapyLongRestWaves(intensity: 0.25, paused: true)
        }
        .frame(width: 2, height: 2)
        // Not zero: SwiftUI skips drawing fully transparent views.
        .opacity(0.01)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
