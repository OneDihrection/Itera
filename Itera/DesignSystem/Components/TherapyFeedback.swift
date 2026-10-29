//
//  TherapyFeedback.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TherapyProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(TherapyPalette.primary.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(TherapyPalette.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.12), value: progress)
        }
        .accessibilityElement()
        .accessibilityLabel("session.holdProgress")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// Visual-only countdown. Its owner supplies monotonic session time and pause behavior.
struct TherapyCountdown: View {
    let remaining: Double
    let total: Double
    let pause: () -> Void
    let stop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height) * 0.72
            Button(action: pause) {
                ZStack {
                    TherapyProgressRing(progress: remaining / max(1, total), lineWidth: 18)
                    Text(verbatim: String(max(0, Int(ceil(remaining)))))
                        .typography(size: 180, weight: .bold, relativeTo: .largeTitle)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: Int(ceil(remaining)))
                        .minimumScaleFactor(0.4)
                        .padding(40)
                }
                .frame(width: diameter, height: diameter)
                .foregroundStyle(TherapyPalette.primary)
            }
            .buttonStyle(TherapySoundButtonStyle())
            .accessibilityLabel("stage.countdown")
            .accessibilityValue(Text(verbatim: String(max(0, Int(ceil(remaining))))))
            .accessibilityHint("countdown.pauseHint")
            .accessibilityAction(named: Text("action.end"), stop)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TherapyPalette.cream.ignoresSafeArea())
    }
}

/// A bounded, deterministic burst; Reduce Motion keeps the success symbol without moving particles.
struct TherapyCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var burstFinished = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: burstFinished)) { timeline in
                    Canvas { context, size in
                        let elapsed = timeline.date.timeIntervalSince(started)
                        guard elapsed < 2.4 else {
                            return
                        }
                        let colors = [TherapyPalette.primary, TherapyPalette.secondary, TherapyPalette.tertiary]
                        for index in 0..<32 {
                            let angle = Double(index) * 2.399
                            let speed = 80 + Double(index % 7) * 23
                            let x = size.width / 2 + cos(angle) * speed * elapsed
                            let y = size.height * 0.35 + sin(angle) * speed * elapsed + 85 * elapsed * elapsed
                            context.opacity = max(0, 1 - elapsed / 2.4)
                            context.fill(
                                Path(roundedRect: CGRect(x: x, y: y, width: 10, height: 16), cornerRadius: 3),
                                with: .color(colors[index % colors.count])
                            )
                        }
                    }
                }
            }
            Image(systemName: "checkmark.seal.fill")
                .accessibilityHidden(true)
                .typography(size: 100, weight: .bold)
                .foregroundStyle(TherapyPalette.primary)
                .padding(30)
                .background(TherapyPalette.secondary, in: Circle())
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(2.4))
            burstFinished = true
        }
    }
}

struct TherapyFeelingChoice: View {
    let title: LocalizedStringKey
    /// -1 is difficult, 0 is just right, 1 is easy.
    let expression: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 26) {
                face.frame(width: 112, height: 112)
                Text(title).typography(.title2)
            }
            .foregroundStyle(selected ? TherapyPalette.primary : TherapyPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 260)
            .padding(18)
            .background(selected ? TherapyPalette.secondary : TherapyPalette.surface,
                        in: RoundedRectangle(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(selected ? TherapyPalette.primary : TherapyPalette.muted.opacity(0.3),
                            lineWidth: selected ? 4 : 1)
            }
        }
        .buttonStyle(TherapySoundButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var face: some View {
        Canvas { context, size in
            let color = selected ? TherapyPalette.primary : TherapyPalette.ink
            context.stroke(Path(ellipseIn: CGRect(x: 5, y: 5, width: 102, height: 102)),
                           with: .color(color), lineWidth: 7)
            for x in [38.0, 74.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 6, y: 38, width: 12, height: 14)), with: .color(color))
            }
            var mouth = Path()
            let edge = expression < 0 ? 84.0 : 74.0
            let control: Double
            switch expression {
            case ..<0: control = 51
            case 1...: control = 103
            default: control = 74
            }
            mouth.move(to: CGPoint(x: 32, y: edge))
            mouth.addQuadCurve(to: CGPoint(x: 80, y: edge), control: CGPoint(x: 56, y: control))
            context.stroke(mouth, with: .color(color), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
