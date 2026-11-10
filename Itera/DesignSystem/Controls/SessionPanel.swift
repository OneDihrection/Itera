//
//  SessionPanel.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct TMSessionPanel<Content: View>: View {
    enum Tone {
        case neutral, guidance, calibration, practice

        var color: Color {
            switch self {
            case .neutral: return .gray
            case .guidance: return .blue
            case .calibration: return .orange
            case .practice: return .green
            }
        }
    }

    private let tone: Tone
    /// Light pages draw the soft grey panel of the finger pages instead of a tinted black one.
    private let light: Bool
    private let content: Content

    init(tone: Tone = .neutral, light: Bool = false, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.light = light
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if light {
            content
                .padding(20)
                .background(TherapyPalette.panel, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content
                .padding(20)
                .background(tone.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                .background(.black, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct TMTargetBubble: View {
    let diameter: Double
    let active: Bool
    let progress: Double

    var body: some View {
        Circle()
            .fill((active ? Color.green : Color.white).opacity(0.18))
            .overlay { Circle().stroke(active ? .green : .white.opacity(0.5), lineWidth: 3) }
            .overlay {
                Circle().trim(from: 0, to: progress)
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}
