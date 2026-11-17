//
//  TowelWorkspaceView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 05/11/2026.
//

import SwiftUI

/// The towel, its grab handle, its drop zone and the patient's hand, drawn over the camera.
///
/// One gesture is shown at a time: pinch on the glowing circle, slide to the goal circle, then open.
/// The towel's moving edge follows the fold progress, so the picture matches the hand. Activity
/// coordinates already include the selected preview reflection, exactly once, so nothing here
/// reflects them again.
struct TMTowelWorkspaceView: View {
    let snapshot: TowelSnapshot

    var interpolates = false
    /// The demonstration is small, so it leaves out the step strip and fold dots.
    var showsHeader = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A critically damped spring retargets from the current value when a new frame arrives, so a
    /// fast fold (or a skipped frame) glides to the new position instead of snapping.
    private var motion: Animation? {
        interpolates && !reduceMotion ? .interactiveSpring(response: 0.16, dampingFraction: 1, blendDuration: 0.1) : nil
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = CameraDisplayGeometry(aspect: snapshot.imageAspect, viewport: proxy.size)

            ZStack {
                board(geometry)
                trail(geometry)
                indicator(geometry)

                if showsHeader {
                    header
                }
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("session.foldTowel"))
    }

    // MARK: - Layers

    private func board(_ geometry: CameraDisplayGeometry) -> some View {
        let size = TowelBoard.panelFraction(foldIndex: snapshot.foldIndex)

        return TMTherapyFoldPanel(
            progress: snapshot.foldProgress,
            horizontal: snapshot.foldIndex % 2 == 0,
            layers: 1 << snapshot.foldIndex,
            fillOpacity: 0.35
        )
        .frame(
            width: geometry.imageRect.width * size.width,
            height: geometry.imageRect.height * size.height
        )
        .position(x: geometry.imageRect.midX, y: geometry.imageRect.midY)
        .animation(motion, value: snapshot.foldProgress)
    }

    private func trail(_ geometry: CameraDisplayGeometry) -> some View {
        TMTowelTrail(
            from: screen(snapshot.grabPoint, geometry),
            to: screen(snapshot.destination, geometry),
            progress: snapshot.foldProgress,
            grabbed: step > 0
        )
    }

    /// Only the zone of the current step, with the hand as a small circle that joins it while the
    /// hand counts as inside (`TMTherapyMergingGuide`, the finger exercises' indicator).
    private func indicator(_ geometry: CameraDisplayGeometry) -> some View {
        let zone = step == 0 ? snapshot.grabPoint : snapshot.destination

        return TMTowelIndicator(
            // Without a hand the point rests inside the zone, so a tracking blink never swaps views.
            hand: snapshot.handPosition ?? zone,
            zone: zone,
            symbol: step == 0 ? Self.grabSymbol : destinationSymbol,
            progress: snapshot.interaction == .readyToRelease ? snapshot.holdProgress : 0,
            showsTimer: snapshot.interaction == .readyToRelease,
            geometry: geometry
        )
        .animation(motion, value: snapshot.handPosition)
    }

    /// Kept to the top corners, away from the path (grab and drop zones sit at the center column
    /// for vertical folds).
    private var header: some View {
        HStack(alignment: .top) {
            TMTherapyStepStrip(steps: TowelBoard.steps, current: step)

            Spacer(minLength: 12)

            TMTherapyProgressDots(
                completed: snapshot.foldIndex,
                total: TowelBoard.foldCount,
                label: "towel.foldNumber \(snapshot.foldIndex + 1)"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    // MARK: - State

    /// 0 grab, 1 slide, 2 release.
    private var step: Int {
        switch snapshot.interaction {
        case .approach:
            return 0
        case .folding, .recovering:
            return 1
        case .readyToRelease:
            return 2
        }
    }

    private static let grabSymbol = "hand.pinch.fill"

    private var destinationSymbol: String {
        if snapshot.interaction == .readyToRelease {
            return "hand.raised.fingers.spread"
        }

        return snapshot.foldIndex % 2 == 0 ? "arrow.left" : "arrow.up"
    }

    private func screen(_ point: TherapyPoint, _ geometry: CameraDisplayGeometry) -> CGPoint {
        geometry.point(CGPoint(x: point.x, y: point.y))
    }
}

// MARK: - Board layout

/// Normalized sizes shared by the workspace and the demonstration, so both draw the same towel.
enum TowelBoard {
    static let foldCount = 4

    /// The acceptance radius is 0.12 of the workspace, so zones are drawn 0.24 across.
    static let zoneDiameter = 0.24

    static let steps = [
        TherapyStep(id: 0, title: "towel.step.grab", symbol: "hand.pinch.fill"),
        TherapyStep(id: 1, title: "towel.step.slide", symbol: "arrow.left.and.right"),
        TherapyStep(id: 2, title: "towel.step.release", symbol: "hand.raised.fingers.spread")
    ]

    /// The towel spans the reach along the fold axis and halves across it after each fold there.
    static func panelFraction(foldIndex: Int) -> CGSize {
        let reach = 0.6
        let priorFoldsAcross = (foldIndex + 1) / 2
        let across = max(0.2, reach / Double(1 << priorFoldsAcross))

        if foldIndex % 2 == 0 {
            return CGSize(width: reach, height: across)
        }

        return CGSize(width: across, height: reach)
    }
}

// MARK: - Indicator

/// The current zone and the hand, drawn with `TMTherapyMergingGuide`.
///
/// Calm on purpose: the hand circle always sits on the hand (the fixed anchor never pulls it), it
/// carries no glyph, and it joins the zone with a short ease, without bounce, only while the hand
/// is within the activity's 0.12 acceptance distance. Animatable over the hand position, so the
/// display spring eases the hand between frames. The zone is drawn as a circle as tall as the 0.24
/// acceptance region; on a wider image the region reaches a little further sideways.
private struct TMTowelIndicator: View, Animatable {
    var hand: TherapyPoint
    let zone: TherapyPoint
    let symbol: String
    let progress: Double
    let showsTimer: Bool
    let geometry: CameraDisplayGeometry

    private static let handDiameter: CGFloat = 48

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(hand.x, hand.y) }
        set { hand = TherapyPoint(x: newValue.first, y: newValue.second) }
    }

    var body: some View {
        TMTherapyMergingGuide(
            first: screen(hand),
            second: screen(zone),
            diameter: geometry.imageRect.height * TowelBoard.zoneDiameter,
            firstDiameter: Self.handDiameter,
            merge: inside ? 1 : 0,
            anchor: .fixed,
            progress: progress,
            active: true,
            showsTimer: showsTimer,
            secondSymbol: symbol,
            mergeAnimation: .easeOut(duration: 0.25)
        )
    }

    private var inside: Bool {
        (hand - zone).length <= TowelBoard.zoneDiameter / 2
    }

    private func screen(_ point: TherapyPoint) -> CGPoint {
        geometry.point(CGPoint(x: point.x, y: point.y))
    }
}

// MARK: - Trail

/// Three chevrons along the path from the handle to the drop zone. Those the towel has already
/// passed fade, and the whole trail recedes once the towel is grabbed.
private struct TMTowelTrail: View {
    let from: CGPoint
    let to: CGPoint
    let progress: Double
    let grabbed: Bool

    var body: some View {
        Canvas { context, _ in
            let angle = atan2(to.y - from.y, to.x - from.x)

            for fraction in [0.3, 0.5, 0.7] {
                let center = CGPoint(
                    x: from.x + (to.x - from.x) * fraction,
                    y: from.y + (to.y - from.y) * fraction
                )
                let passed = progress > fraction
                let opacity = passed ? 0.2 : (grabbed ? 0.6 : 0.95)

                var chevron = Path()
                chevron.move(to: CGPoint(x: -9, y: -16))
                chevron.addLine(to: CGPoint(x: 9, y: 0))
                chevron.addLine(to: CGPoint(x: -9, y: 16))

                let placed = chevron
                    .applying(CGAffineTransform(rotationAngle: angle))
                    .applying(CGAffineTransform(translationX: center.x, y: center.y))
                let style = StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                let underlay = StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)

                context.stroke(placed, with: .color(TherapyPalette.calmUnderlay.opacity(opacity)), style: underlay)
                context.stroke(placed, with: .color(.white.opacity(opacity)), style: style)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Towel fold") {
    var snapshot = TowelSnapshot()
    snapshot.phase = .practice
    snapshot.interaction = .folding
    snapshot.foldProgress = 0.4
    snapshot.handPosition = TherapyPoint(x: 0.55, y: 0.5)
    snapshot.grip = .closed

    return TMTowelWorkspaceView(snapshot: snapshot)
        .frame(width: 700, height: 560)
        .background(.gray)
        .foregroundStyle(.white)
}
#endif
