//
//  TherapyProgressDots.swift
//  Itera
//
//  Created by dimaswisodewo on 06/11/2026.
//

import SwiftUI

/// Quiet repetition progress for the camera view: one soft dot per repetition, no counters.
///
/// Long goals fall back to a thin bar so the row never wraps or crowds the preview.
struct TherapyProgressDots: View {
    let completed: Int
    let total: Int
    var label: LocalizedStringKey

    private let maximumDots = 12

    var body: some View {
        let done = min(max(0, completed), max(0, total))

        content(done: done)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.65), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text("\(done) / \(total)"))
    }

    @ViewBuilder
    private func content(done: Int) -> some View {
        if total <= maximumDots {
            HStack(spacing: 12) {
                ForEach(0..<max(0, total), id: \.self) { index in
                    Circle()
                        .fill(index < done ? TherapyPalette.guidanceBlue : .clear)
                        .overlay {
                            Circle().strokeBorder(TherapyPalette.guidanceBlue, lineWidth: 3)
                        }
                        .frame(width: 24, height: 24)
                }
            }
        } else {
            ProgressView(value: Double(done), total: Double(max(1, total)))
                .tint(TherapyPalette.guidanceBlue)
                .frame(width: 200)
        }
    }
}
