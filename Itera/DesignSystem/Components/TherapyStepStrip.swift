//
//  TherapyStepStrip.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import SwiftUI

/// One step of a short guided gesture.
struct TherapyStep: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    let symbol: String
}

/// A compact strip over the camera that shows where the patient is in a short gesture: finished
/// steps carry a check, the current step shows its name, and later steps show only their icon.
///
/// It displays the supplied index only; the caller decides what the current step is.
struct TherapyStepStrip: View {
    let steps: [TherapyStep]
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps) { step in
                chip(for: step)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.65), in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(currentTitle)
        .accessibilityValue(Text("\(min(current, steps.count - 1) + 1) / \(steps.count)"))
    }

    private var currentTitle: Text {
        guard steps.indices.contains(current) else {
            return Text(verbatim: "")
        }

        return Text(steps[current].title)
    }

    private func chip(for step: TherapyStep) -> some View {
        let done = step.id < current
        let active = step.id == current

        return HStack(spacing: 8) {
            Image(systemName: done ? "checkmark" : step.symbol)
                .typography(size: 20, weight: .bold)

            if active {
                Text(step.title)
                    .typography(size: 20, weight: .bold, relativeTo: .headline)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(active ? Color.black : (done ? TherapyPalette.calmTeal : Color.white.opacity(0.7)))
        .padding(.horizontal, 12)
        .frame(minWidth: 44, minHeight: 44)
        .background(active ? TherapyPalette.calmTeal : Color.clear, in: Capsule())
    }
}

#if DEBUG
#Preview("Step strip") {
    VStack(spacing: 20) {
        ForEach(0..<3, id: \.self) { index in
            TherapyStepStrip(
                steps: [
                    TherapyStep(id: 0, title: "Grab", symbol: "hand.raised.fill"),
                    TherapyStep(id: 1, title: "Slide", symbol: "arrow.left"),
                    TherapyStep(id: 2, title: "Release", symbol: "hand.raised.fingers.spread")
                ],
                current: index
            )
        }
    }
    .padding(40)
    .background(.gray)
}
#endif
