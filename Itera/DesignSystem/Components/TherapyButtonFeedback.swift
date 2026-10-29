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
        .buttonStyle(.plain)
    }
}
