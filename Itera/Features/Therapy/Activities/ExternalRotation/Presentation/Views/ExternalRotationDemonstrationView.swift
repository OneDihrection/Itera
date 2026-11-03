//
//  ExternalRotationDemonstrationView.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import SwiftUI

/// Chooses the movement preview for a Balancing-style exercise: the bundled 3D animation for
/// cross-midline reaching, and a native illustration for external rotation.
struct BalanceExerciseDemonstrationView: View {
    let exercise: BalanceExercise
    let paused: Bool

    var body: some View {
        switch exercise {
        case .crossMidline:
            BalanceDemonstrationView(paused: paused)
        case .externalRotation, .internalRotation:
            ExternalRotationDemonstrationView(direction: exercise.rotationDirection, paused: paused)
        case .shoulderFlexion:
            ShoulderFlexionDemonstrationView(paused: paused)
        }
    }
}

/// A front view of an arm with the elbow at the side, turning the forearm from pointing at the
/// viewer out to the side (external) or in across the belly (internal), and back. A native stand-in until a rendered animation is bundled.
struct ExternalRotationDemonstrationView: View {
    let direction: RotationDirection
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cycle = 4.0

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: paused || reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(&context, size: size, turn: turn(at: timeline.date))
                }
            }
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: paused ? "pause.fill" : "waveform.path")
                    Text(paused ? "balance.animationPaused" : "balance.animationPlaying")
                }
                .typography(.footnote)
                .foregroundStyle(TherapyPalette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
            }
        }
        .background(TherapyPalette.mediaBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(TherapyPalette.green.opacity(0.18), lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LocalizedStringKey(direction == .outward ? "rotation.animationAccessibility" : "internalRotation.animationAccessibility"))
    }

    /// 0 with the forearm pointing at the viewer, 1 with it turned fully outward.
    private func turn(at date: Date) -> Double {
        guard !paused, !reduceMotion else {
            return 0.7
        }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return 0.5 - 0.5 * cos(phase * 2 * .pi)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, turn: Double) {
        let unit = min(size.width, size.height * 1.2) / 6
        let shoulder = CGPoint(x: size.width * 0.38, y: size.height * 0.2)
        let elbow = CGPoint(x: shoulder.x, y: shoulder.y + unit * 1.6)
        // Seen from the front, the forearm is foreshortened until it turns out of the viewing axis.
        // The torso is drawn to the right of the arm, so outward is left and inward is right.
        let reach = unit * 1.5 * sin(turn * .pi / 2) * (direction == .outward ? -1 : 1)
        let wrist = CGPoint(x: elbow.x + reach, y: elbow.y + unit * 0.25 * (1 - turn))
        let torso = CGRect(x: shoulder.x - unit * 0.1, y: shoulder.y - unit * 0.2, width: unit * 1.7, height: unit * 3.6)
            .offsetBy(dx: unit * 0.25, dy: 0)
        context.fill(Path(roundedRect: torso, cornerRadius: unit * 0.4), with: .color(TherapyPalette.hero))
        var arm = Path()
        arm.move(to: shoulder)
        arm.addLine(to: elbow)
        arm.addLine(to: wrist)
        context.stroke(arm, with: .color(TherapyPalette.green), style: StrokeStyle(lineWidth: unit * 0.28, lineCap: .round, lineJoin: .round))
        for point in [shoulder, elbow, wrist] {
            let rect = CGRect(x: point.x - unit * 0.2, y: point.y - unit * 0.2, width: unit * 0.4, height: unit * 0.4)
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(Path(ellipseIn: rect), with: .color(TherapyPalette.green), lineWidth: 4)
        }
        if turn > 0.05 {
            var guide = Path()
            guide.addArc(
                center: elbow, radius: unit * 1.1,
                startAngle: .degrees(90), endAngle: .degrees(90 + (direction == .outward ? 90 : -90) * turn),
                clockwise: direction == .inward
            )
            context.stroke(guide, with: .color(TherapyPalette.warning), style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
        }
    }
}
