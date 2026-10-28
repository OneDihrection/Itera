//
//  SessionCelebration.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

/// A screen-sized shower driven by the controller's single celebration clock.
struct SessionCelebration: View {
    let start: Date
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: finished)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                if elapsed >= 0, elapsed < 3 {
                    let colors: [Color] = [.orange, .pink, .teal, .blue, .purple]

                    // Stable seeds keep trajectories continuous across redraws and rotation.
                    for index in 0..<180 {
                        let seed = Double(index)
                        let delay = Double(index % 9) * 0.04
                        let age = elapsed - delay
                        guard age >= 0 else { continue }

                        let progress = age / 3
                        let originX = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1)
                        let originY = (seed * 0.41421356237).truncatingRemainder(dividingBy: 1)
                        let drift = sin(seed * 2.4 + age * 1.8) * 0.045
                        let x = size.width * (originX + drift)
                        let y = size.height * (
                            originY * 1.3 - 0.45
                            + progress * (0.65 + Double(index % 5) * 0.08)
                            + 0.25 * progress * progress
                        )
                        let width = Double(12 + index % 9)
                        let height = Double(8 + index % 7)

                        var particle = context
                        particle.opacity = min(1, (3 - elapsed) / 0.8)
                        particle.translateBy(x: x, y: y)
                        particle.rotate(by: .radians(seed + age * (index.isMultiple(of: 2) ? 2 : -2)))
                        particle.fill(
                            Path(CGRect(x: -width / 2, y: -height / 2, width: width, height: height)),
                            with: .color(colors[index % colors.count])
                        )
                    }
                }
            }
        }
        .task(id: start) {
            finished = false
            do {
                try await Task.sleep(for: .seconds(3))
                finished = true
            } catch { }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
