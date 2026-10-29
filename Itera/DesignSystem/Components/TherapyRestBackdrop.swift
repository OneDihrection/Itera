//
//  TherapyRestBackdrop.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

/// A decorative garden with slow waves and floating leaves; it owns no exercise timing.
struct TherapyRestBackdrop: View {
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: paused || reduceMotion || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                drawWaves(context: &context, size: size, time: time)
                drawLeaves(context: &context, size: size, time: time)
                let breath = 1 + sin(time / 4) * 0.04
                let diameter = min(size.width, size.height) * 0.72 * breath
                let halo = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2,
                                  width: diameter, height: diameter)
                context.fill(Path(ellipseIn: halo), with: .color(TherapyPalette.secondary.opacity(0.45)))
            }
        }
        .background(TherapyPalette.cream)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawWaves(context: inout GraphicsContext, size: CGSize, time: Double) {
        let colors = [TherapyPalette.secondary, TherapyPalette.tertiary, TherapyPalette.primary.opacity(0.10)]
        for layer in 0..<3 {
            let baseline = size.height * (0.70 + Double(layer) * 0.10)
            let shift = sin(time / 6 + Double(layer)) * 18
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: baseline + shift))
            wave.addCurve(to: CGPoint(x: size.width, y: baseline - shift),
                          control1: CGPoint(x: size.width * 0.3, y: baseline - 55 + shift),
                          control2: CGPoint(x: size.width * 0.7, y: baseline + 55 - shift))
            wave.addLine(to: CGPoint(x: size.width, y: size.height))
            wave.addLine(to: CGPoint(x: 0, y: size.height))
            wave.closeSubpath()
            context.fill(wave, with: .color(colors[layer].opacity(0.7)))
        }
    }

    private func drawLeaves(context: inout GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<10 {
            let seed = Double(index)
            let x = size.width * (0.05 + seed * 0.10) + sin(time / 7 + seed) * 14
            let y = size.height * (0.15 + Double(index % 4) * 0.16) + cos(time / 9 + seed) * 18
            var leaf = context
            leaf.translateBy(x: x, y: y)
            leaf.rotate(by: .degrees(seed * 37 + sin(time / 8 + seed) * 8))
            leaf.fill(Path(ellipseIn: CGRect(x: -9, y: -19, width: 18, height: 38)),
                      with: .color(TherapyPalette.primary.opacity(0.10)))
        }
    }
}
