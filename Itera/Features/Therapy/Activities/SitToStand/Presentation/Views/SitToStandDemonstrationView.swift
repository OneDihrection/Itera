//
//  SitToStandDemonstrationView.swift
//  Itera
//
//  Created by Fauzan Azima on 09/11/2026.
//

import SwiftUI

/// A side view of sit-to-stand with a controlled forward lean: sit, lean forward, stand, then sit
/// back down slowly. A native stand-in until a rendered animation is bundled.
struct SitToStandDemonstrationView: View {
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cycle = 7.0

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: paused || reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(&context, size: size, pose: pose(at: timeline.date))
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
        .accessibilityLabel("sitToStand.animationAccessibility")
    }

    /// The knee angle (90° seated, 175° standing) and trunk lean from vertical, in degrees.
    private struct Pose {
        var knee: Double
        var lean: Double
    }

    private func pose(at date: Date) -> Pose {
        guard !paused, !reduceMotion else {
            return Pose(knee: 90, lean: 28)
        }

        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle

        switch phase {
        case ..<0.15:
            return Pose(knee: 90, lean: 4)
        case ..<0.35:
            return Pose(knee: 90, lean: 4 + 24 * ease((phase - 0.15) / 0.20))
        case ..<0.60:
            let rise = ease((phase - 0.35) / 0.25)

            return Pose(knee: 90 + 85 * rise, lean: 28 - 22 * rise)
        case ..<0.70:
            return Pose(knee: 175, lean: 6)
        default:
            let lower = ease((phase - 0.70) / 0.30)

            return Pose(knee: 175 - 85 * lower, lean: 6 - 2 * lower)
        }
    }

    private func ease(_ value: Double) -> Double {
        0.5 - 0.5 * cos(min(1, max(0, value)) * .pi)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, pose: Pose) {
        let unit = min(size.width / 3.4, size.height / 4.4)
        let floorY = size.height * 0.88
        let ankle = CGPoint(x: size.width * 0.58, y: floorY)
        let knee = CGPoint(x: ankle.x, y: ankle.y - unit)

        // The thigh swings from horizontal (90° at the knee) up to vertical (180°).
        let kneeAngle = pose.knee * .pi / 180
        let hip = CGPoint(
            x: knee.x - unit * sin(kneeAngle),
            y: knee.y + unit * cos(kneeAngle)
        )

        let lean = pose.lean * .pi / 180
        let direction = CGPoint(x: sin(lean), y: -cos(lean))
        let shoulder = CGPoint(x: hip.x + direction.x * unit * 1.3, y: hip.y + direction.y * unit * 1.3)
        let head = CGPoint(x: shoulder.x + direction.x * unit * 0.45, y: shoulder.y + direction.y * unit * 0.45)

        var floor = Path()
        floor.move(to: CGPoint(x: size.width * 0.08, y: floorY))
        floor.addLine(to: CGPoint(x: size.width * 0.92, y: floorY))
        context.stroke(floor, with: .color(TherapyPalette.muted.opacity(0.5)), lineWidth: 3)

        // The chair stays where the patient started.
        let seatY = knee.y + unit * 0.12
        let seat = CGRect(x: ankle.x - unit * 1.55, y: seatY, width: unit * 1.5, height: unit * 0.16)
        context.fill(Path(roundedRect: seat, cornerRadius: 6), with: .color(TherapyPalette.hero))
        var back = Path()
        back.move(to: CGPoint(x: seat.minX + 4, y: seatY))
        back.addLine(to: CGPoint(x: seat.minX + 4, y: seatY - unit * 1.1))
        back.move(to: CGPoint(x: seat.minX + 12, y: seat.maxY))
        back.addLine(to: CGPoint(x: seat.minX + 12, y: floorY))
        back.move(to: CGPoint(x: seat.maxX - 12, y: seat.maxY))
        back.addLine(to: CGPoint(x: seat.maxX - 12, y: floorY))
        context.stroke(back, with: .color(TherapyPalette.hero), style: StrokeStyle(lineWidth: 8, lineCap: .round))

        var body = Path()
        body.move(to: ankle)
        body.addLine(to: knee)
        body.addLine(to: hip)
        body.addLine(to: shoulder)
        context.stroke(
            body,
            with: .color(TherapyPalette.green),
            style: StrokeStyle(lineWidth: unit * 0.26, lineCap: .round, lineJoin: .round)
        )

        for point in [ankle, knee, hip, shoulder] {
            let rect = CGRect(x: point.x - unit * 0.18, y: point.y - unit * 0.18, width: unit * 0.36, height: unit * 0.36)
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(Path(ellipseIn: rect), with: .color(TherapyPalette.green), lineWidth: 4)
        }

        let headRect = CGRect(x: head.x - unit * 0.26, y: head.y - unit * 0.26, width: unit * 0.52, height: unit * 0.52)
        context.fill(Path(ellipseIn: headRect), with: .color(TherapyPalette.green))

        // The lean the exercise asks for, marked from the hip while the trunk is tilted forward.
        if pose.lean > 8 {
            var guide = Path()
            guide.addArc(
                center: hip,
                radius: unit * 0.8,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + pose.lean),
                clockwise: false
            )
            context.stroke(guide, with: .color(TherapyPalette.warning), style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
        }
    }
}
