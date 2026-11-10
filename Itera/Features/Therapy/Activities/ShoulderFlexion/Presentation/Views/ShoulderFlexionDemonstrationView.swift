//
//  ShoulderFlexionDemonstrationView.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import SwiftUI

/// A front view of an arm swinging from hanging at the side, forward and all the way overhead with
/// the palm turned up and the arm rotated outward, then back down. A native stand-in until a rendered animation is bundled.
struct TMShoulderFlexionDemonstrationView: View {
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cycle = 5.0

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: paused || reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(&context, size: size, lift: lift(at: timeline.date))
                }
            }
            TMTherapyDemoCaption(paused: paused)
        }
        .background(TherapyPalette.mediaBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(TherapyPalette.green.opacity(0.18), lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("shoulderFlexion.animationAccessibility")
    }

    /// 0 with the arm hanging, 1 with it raised fully overhead.
    private func lift(at date: Date) -> Double {
        guard !paused, !reduceMotion else {
            return 0.5
        }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return 0.5 - 0.5 * cos(phase * 2 * .pi)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, lift: Double) {
        // The shoulder sits mid-height so the arm has room to swing a full half circle.
        let armLength = size.height * 0.36
        let unit = armLength / 2.6
        let shoulder = CGPoint(x: size.width * 0.38, y: size.height * 0.5)
        // From the front a forward-raised arm is foreshortened: its wrist climbs but barely moves sideways.
        let angle = lift * .pi
        let wrist = CGPoint(
            x: shoulder.x - unit * 0.5 * sin(angle),
            y: shoulder.y + armLength * cos(angle)
        )
        let elbow = CGPoint(
            x: shoulder.x - unit * 0.3 * sin(angle),
            y: shoulder.y + armLength * 0.5 * cos(angle)
        )
        let torso = CGRect(x: shoulder.x - unit * 0.1, y: shoulder.y - unit * 0.2, width: unit * 1.7, height: unit * 3.2)
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
        if lift > 0.05 {
            var guide = Path()
            guide.move(to: CGPoint(x: shoulder.x + unit * 0.9, y: shoulder.y + armLength))
            guide.addLine(to: CGPoint(x: shoulder.x + unit * 0.9, y: wrist.y))
            context.stroke(guide, with: .color(TherapyPalette.warning), style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
        }
    }
}
