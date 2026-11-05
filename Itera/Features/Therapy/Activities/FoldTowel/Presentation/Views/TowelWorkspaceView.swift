//
//  TowelWorkspaceView.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import SwiftUI

struct TowelWorkspaceView: View {
    let snapshot: TowelSnapshot

    var interpolates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? {
        interpolates && !reduceMotion ? .linear(duration: 0.05) : nil
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = CameraDisplayGeometry(aspect: snapshot.imageAspect, viewport: proxy.size)
            let size = geometry.imageRect.size
            ZStack {
                TherapyFoldPanel(
                    progress: snapshot.foldProgress,
                    horizontal: snapshot.foldIndex % 2 == 0,
                    layers: 1 << snapshot.foldIndex,
                    fillOpacity: 0.35
                )
                .frame(width: size.width * (snapshot.foldIndex % 2 == 0 ? 0.6 : 0.3), height: size.height * 0.6)
                .position(x: geometry.imageRect.midX, y: geometry.imageRect.midY)
                .animation(motion, value: snapshot.foldProgress)

                Path { path in
                    path.move(to: screen(snapshot.grabPoint, geometry: geometry))
                    path.addLine(to: screen(snapshot.destination, geometry: geometry))
                }
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))

                target(symbol: "hand.raised", color: .yellow, size: size,
                       progress: snapshot.interaction == .grabbing ? snapshot.holdProgress : 0)
                    .position(screen(snapshot.grabPoint, geometry: geometry))
                target(symbol: snapshot.interaction == .readyToRelease ? "hand.raised.fill" : (snapshot.foldIndex % 2 == 0 ? "arrow.left" : "arrow.up"),
                       color: .green, size: size,
                       progress: snapshot.interaction == .destinationHold || snapshot.interaction == .readyToRelease ? snapshot.holdProgress : 0)
                    .position(screen(snapshot.destination, geometry: geometry))
                if let hand = snapshot.handPosition {
                    marker(symbol: snapshot.grip == .closed ? "hand.point.up.braille.fill" : "hand.raised.fill",
                           color: grabbed ? .green : .orange)
                        .position(screen(hand, geometry: geometry))
                        .animation(motion, value: hand)
                }
                progressMarks
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("session.foldTowel"))
    }

    private var grabbed: Bool {
        snapshot.interaction == .folding || snapshot.interaction == .destinationHold
            || snapshot.interaction == .readyToRelease
    }

    private var progressMarks: some View {
        HStack(spacing: 12) {
            Text("towel.foldNumber \(snapshot.foldIndex + 1)")
                .typography(.headline)
            ForEach(0..<4) { index in
                Image(systemName: index < snapshot.foldIndex ? "checkmark.circle.fill" : "circle")
            }
        }
        .padding(12)
        .background(.black.opacity(0.65), in: Capsule())
    }

    private func screen(_ point: TherapyPoint, geometry: CameraDisplayGeometry) -> CGPoint {
        // Activity coordinates already include the selected preview reflection, exactly once.
        geometry.point(CGPoint(x: point.x, y: point.y))
    }

    private func target(symbol: String, color: Color, size: CGSize, progress: Double) -> some View {
        Ellipse()
            .fill(color.opacity(0.12))
            .overlay(Ellipse().stroke(color, lineWidth: 3))
            .overlay {
                Ellipse().trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }
            .overlay { marker(symbol: symbol, color: color) }
            .frame(width: size.width * 0.24, height: size.height * 0.24)
            .accessibilityHidden(true)
    }

    private func marker(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .typography(.title)
            .foregroundStyle(color)
            .frame(width: 68, height: 68)
            .background(.black.opacity(0.65), in: Circle())
            .overlay(Circle().stroke(color, lineWidth: 3))
            .accessibilityHidden(true)
    }
}

struct TowelDemonstrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let step = Int(elapsed / 4) % 4
            let progress = reduceMotion ? 0.35 : min(1, max(0, (elapsed.truncatingRemainder(dividingBy: 4) - 1) / 2))
            TherapyFoldPanel(progress: progress, horizontal: step % 2 == 0, layers: 1 << step)
                .padding(40)
        }
    }
}

#if DEBUG
#Preview("Towel fold") {
    var snapshot = TowelSnapshot()
    snapshot.phase = .practice
    snapshot.foldProgress = 0.4
    snapshot.handPosition = TherapyPoint(x: 0.55, y: 0.5)
    snapshot.grip = .closed
    return TowelWorkspaceView(snapshot: snapshot)
        .frame(width: 1000, height: 600)
        .foregroundStyle(.white)
}
#endif
