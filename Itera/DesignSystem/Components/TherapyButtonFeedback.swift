//
//  TherapyButtonFeedback.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

private struct ButtonFeedbackKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var buttonFeedback: @MainActor () -> Void {
        get { self[ButtonFeedbackKey.self] }
        set { self[ButtonFeedbackKey.self] = newValue }
    }
}

/// Feedback follows activation, including accessibility activation, rather than a competing tap gesture.
struct TherapySoundButtonStyle: PrimitiveButtonStyle {
    @Environment(\.buttonFeedback) private var feedback

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            feedback()
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(TherapyPressFeedbackStyle())
    }
}

private struct TherapyPressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
