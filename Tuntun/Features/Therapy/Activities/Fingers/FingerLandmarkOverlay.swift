//
//  FingerLandmarkOverlay.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

/// Draws the guide circles on the tracked fingertips over the camera preview.
///
/// Sizes follow the hand's size on screen, so a hand farther from the camera gets smaller
/// circles. Text never sits on the hand: circles show only their progress ring, and the
/// remaining time appears once, beside the hand.
struct TMFingerLandmarkOverlay: View {
    let evidence: HandEvidence
    let progress: Double
    let exercise: FingerExercise
    let finger: Int
    let returning: Bool
    let showsTimer: Bool
    let guiding: Bool
    /// Full and hook fist: how open the hand is (1 open, 0 closed), which sizes the whole-hand
    /// circle. Nil keeps the open size.
    var openness: Double? = nil
    var completionID: UUID? = nil
    var onCompletionPresented: (UUID) -> Void = { _ in }

    /// Joints drawn at the confidence scoring accepts, so the ring on a touching fingertip
    /// (which Vision rates lower) stays on screen while that fingertip is being scored.
    private static let drawnConfidence: Float = 0.3

    // MARK: - Sizing

    /// Fingertip circle diameters relative to the on-screen palm length (wrist to middle knuckle).
    private static let activeCircleRatio = 0.46
    private static let inactiveCircleRatio = 0.32
    private static let activeCircleRange: ClosedRange<CGFloat> = 44...92
    private static let inactiveCircleRange: ClosedRange<CGFloat> = 28...64
    /// Rounding step, so sizes do not shimmer with small tracking changes.
    private static let sizeStep: CGFloat = 4
    /// Palm length assumed when the wrist or middle knuckle is not visible.
    private static let fallbackPalm: CGFloat = 150
    /// Whole-hand circle diameter in palm lengths: an open hand reaches about one palm length
    /// from the middle knuckle to the wrist and to the fingertips, plus room for a spread thumb.
    private static let handCircleRatio: CGFloat = 2.3
    /// Whole-hand circle diameter around a closed fist, in palm lengths.
    private static let closedHandCircleRatio: CGFloat = 1.3
    private static let minimumHandCircle: CGFloat = 100
    /// Eases the whole-hand and thumb-opposition circles between 30 Hz tracking samples without
    /// visible lag.
    private static let circleGlide: Animation = .interpolatingSpring(duration: 0.15, bounce: 0)

    // MARK: - Thumb opposition merge

    /// Thumb and target circles start to flow together at this fingertip gap, in palm lengths…
    private static let mergeStartRatio: CGFloat = 0.75
    /// …and are one circle at this gap: the 0.45-palm distance up to which scoring keeps a
    /// contact, so a credited touch always shows one circle without forcing it.
    private static let mergeEndRatio: CGFloat = 0.45

    var body: some View {
        GeometryReader { geometry in
            // The preview fills its frame (aspect-fill), so the image covers it and overflows the sides.
            let scale = max(geometry.size.width / evidence.width, geometry.size.height / evidence.height)
            let width = evidence.width * scale
            let height = evidence.height * scale
            let origin = CGPoint(x: (geometry.size.width - width) / 2, y: (geometry.size.height - height) / 2)
            let palm = palmLength(width: width, height: height, origin: origin)

            Canvas { context, _ in
                drawLandmarks(in: &context, palm: palm, width: width, height: height, origin: origin, viewport: geometry.size)
            }

            circles(palm: palm, width: width, height: height, origin: origin, viewport: geometry.size)

        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    // MARK: - Drawing

    /// Draws the short connector from a fingertip to its circle when the circle was pushed
    /// inside the preview edge.
    ///
    /// No skeleton lines or joint dots are drawn: the patient follows the fingertip circles,
    /// and the rest cluttered the hand without guiding it.
    private func drawLandmarks(
        in context: inout GraphicsContext,
        palm: CGFloat,
        width: Double,
        height: Double,
        origin: CGPoint,
        viewport: CGSize
    ) {
        // Connectors thin out a little for a smaller, farther hand.
        let lineWidth = min(4, max(2, palm * 0.025))

        if !usesWholeHandCircle {
            for (index, joint) in [4, 8, 12, 16, 20].enumerated()
            where showsBubble(index + 1)
                && !mergesWithThumb(index + 1)
                && evidence.points[joint].confidence >= Self.drawnConfidence {
                let anchor = point(joint, width: width, height: height, origin: origin)
                let center = fingertipCircleCenter(
                    index + 1, joint: joint, palm: palm,
                    width: width, height: height, origin: origin, viewport: viewport
                )
                if hypot(anchor.x - center.x, anchor.y - center.y) > 1 {
                    var line = Path()
                    line.move(to: anchor)
                    line.addLine(to: center)
                    context.stroke(line, with: .color(TherapyPalette.guidanceOrange), lineWidth: max(2, lineWidth - 1))
                }
            }
        }
    }

    @ViewBuilder
    private func circles(palm: CGFloat, width: Double, height: Double, origin: CGPoint, viewport: CGSize) -> some View {
        if usesWholeHandCircle {
            if let circle = handCircle(palm: palm, width: width, height: height, origin: origin, viewport: viewport) {
                // No fill, so the hand inside the circle stays fully visible.
                TMTherapyMergingGuide(
                    center: circle.center,
                    diameter: circle.diameter,
                    progress: progress,
                    active: guiding,
                    showsTimer: showsTimer,
                    completionID: completionID,
                    onCompletionPresented: onCompletionPresented,
                    popsOnCompletion: true,
                    filled: false,
                    glide: Self.circleGlide
                )
            }
        } else {
            if let pair = oppositionPair(palm: palm, width: width, height: height, origin: origin, viewport: viewport) {
                TMTherapyMergingGuide(
                    first: pair.thumb,
                    second: pair.target,
                    // Unstepped: the glide smooths it, and steps would show as jumps.
                    diameter: fingertipDiameter(active: true, palm: palm, stepped: false),
                    merge: pair.merge,
                    progress: progress,
                    active: true,
                    showsTimer: showsTimer,
                    completionID: completionID,
                    onCompletionPresented: onCompletionPresented,
                    popsOnCompletion: true,
                    glide: Self.circleGlide
                )
            }

            ForEach(Array([4, 8, 12, 16, 20].enumerated()), id: \.offset) { index, joint in
                if showsBubble(index + 1)
                    && !mergesWithThumb(index + 1)
                    && evidence.points[joint].confidence >= Self.drawnConfidence {
                    TMTherapyGuideBubble(
                        // No finger numbers: the instruction names the finger to move.
                        progress: progress,
                        active: isActive(index + 1),
                        completionID: isActive(index + 1) ? completionID : nil,
                        onCompletionPresented: onCompletionPresented,
                        showsTimer: showsTimer && isActive(index + 1),
                        diameter: fingertipDiameter(active: isActive(index + 1), palm: palm),
                        tint: TherapyPalette.guidanceOrange,
                        popsOnCompletion: true
                    )
                    .position(fingertipCircleCenter(
                        index + 1, joint: joint, palm: palm,
                        width: width, height: height, origin: origin, viewport: viewport
                    ))
                }
            }
        }
    }

    // MARK: - Geometry

    private var usesWholeHandCircle: Bool {
        exercise == .fullFist || exercise == .hookFist || exercise == .forearmRotation
    }

    /// The wrist and middle knuckle, which anchor the palm length and the whole-hand circle.
    private var hasPalmAnchors: Bool {
        evidence.points[0].confidence >= Self.drawnConfidence
            && evidence.points[9].confidence >= Self.drawnConfidence
    }

    /// On-screen distance from the wrist to the middle-finger knuckle: a steady size cue that
    /// barely changes while the fingers bend.
    private func palmLength(width: Double, height: Double, origin: CGPoint) -> CGFloat {
        guard hasPalmAnchors else {
            return Self.fallbackPalm
        }

        let wrist = point(0, width: width, height: height, origin: origin)
        let knuckle = point(9, width: width, height: height, origin: origin)
        return hypot(wrist.x - knuckle.x, wrist.y - knuckle.y)
    }

    /// `stepped: false` keeps the exact size, for a circle that glides between samples.
    private func fingertipDiameter(active: Bool, palm: CGFloat, stepped: Bool = true) -> CGFloat {
        let ratio = active ? Self.activeCircleRatio : Self.inactiveCircleRatio
        let range = active ? Self.activeCircleRange : Self.inactiveCircleRange
        let diameter = min(range.upperBound, max(range.lowerBound, palm * ratio))

        guard stepped else {
            return diameter
        }

        return Self.stepped(diameter)
    }

    private static func stepped(_ value: CGFloat) -> CGFloat {
        (value / sizeStep).rounded() * sizeStep
    }

    /// The visible hand's bounding box in preview coordinates.
    private func handBounds(width: Double, height: Double, origin: CGPoint) -> CGRect? {
        let visible = evidence.points.indices
            .filter { evidence.points[$0].confidence >= Self.drawnConfidence }
            .map { point($0, width: width, height: height, origin: origin) }

        guard let first = visible.first else {
            return nil
        }

        return visible.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, location in
            bounds.union(CGRect(origin: location, size: .zero))
        }
    }

    /// A circle around the hand, kept fully on screen.
    ///
    /// It is centred on the middle knuckle and sized from the palm length, which barely change
    /// while the fingers open and close. In full and hook fist it grows as the hand opens and
    /// shrinks as it closes, following `openness`; in forearm rotation it keeps one size. The
    /// joint bounding box jumps as joints cross the confidence threshold, so it is used only
    /// when the wrist or middle knuckle is not visible.
    private func handCircle(
        palm: CGFloat,
        width: Double,
        height: Double,
        origin: CGPoint,
        viewport: CGSize
    ) -> (center: CGPoint, diameter: CGFloat)? {
        // Keep the complete stroke inside the preview, including on smaller windows.
        let available = min(viewport.width, viewport.height) - 40

        guard available > 0,
              let anchor = handCircleAnchor(palm: palm, width: width, height: height, origin: origin) else {
            return nil
        }

        let diameter = min(available * 0.75, max(Self.minimumHandCircle, anchor.diameter))
        let inset = diameter / 2 + 20
        let center = CGPoint(
            x: min(viewport.width - inset, max(inset, anchor.center.x)),
            y: min(viewport.height - inset, max(inset, anchor.center.y))
        )

        return (center, diameter)
    }

    /// The unclamped circle: from the palm anchors when both are visible, otherwise from the
    /// visible joints' bounding box.
    private func handCircleAnchor(
        palm: CGFloat,
        width: Double,
        height: Double,
        origin: CGPoint
    ) -> (center: CGPoint, diameter: CGFloat)? {
        if hasPalmAnchors {
            return (
                point(9, width: width, height: height, origin: origin),
                palm * handCircleRatio
            )
        }

        guard let bounds = handBounds(width: width, height: height, origin: origin) else {
            return nil
        }

        return (
            CGPoint(x: bounds.midX, y: bounds.midY),
            // Unstepped: the glide smooths it, and steps would show as jumps.
            hypot(bounds.width, bounds.height) * 1.03
        )
    }

    /// Whole-hand circle diameter in palm lengths: from the closed to the open size with the
    /// grip's openness, and the open size otherwise.
    private var handCircleRatio: CGFloat {
        guard let openness else {
            return Self.handCircleRatio
        }

        let open = CGFloat(min(1, max(0, openness)))

        return Self.closedHandCircleRatio + (Self.handCircleRatio - Self.closedHandCircleRatio) * open
    }

    private func fingertipCircleCenter(
        _ number: Int,
        joint: Int,
        palm: CGFloat,
        width: Double,
        height: Double,
        origin: CGPoint,
        viewport: CGSize
    ) -> CGPoint {
        let anchor = point(joint, width: width, height: height, origin: origin)
        let radius = fingertipDiameter(active: isActive(number), palm: palm) / 2
        let horizontalInset = min(radius + 10, viewport.width / 2)
        let verticalInset = min(radius + 10, viewport.height / 2)
        return CGPoint(
            x: min(viewport.width - horizontalInset, max(horizontalInset, anchor.x)),
            y: min(viewport.height - verticalInset, max(verticalInset, anchor.y))
        )
    }

    /// While thumb opposition is guided, the thumb and target circles are drawn together by
    /// `TMTherapyMergingGuide` instead of as two separate bubbles.
    private var mergesThumbAndTarget: Bool {
        exercise == .opposition && guiding
    }

    private func mergesWithThumb(_ number: Int) -> Bool {
        mergesThumbAndTarget && (number == 1 || number == finger + 2)
    }

    /// The thumb and target circle centres and how far they have merged (0 apart, 1 one circle).
    ///
    /// Merging follows only the on-screen fingertip gap relative to the palm, so the circles are
    /// one exactly while the tips touch and return to their own fingers as soon as they part.
    /// Hold progress is not used: the open-hand holds (start position, returning) also report
    /// progress while the fingers are apart.
    private func oppositionPair(
        palm: CGFloat,
        width: Double,
        height: Double,
        origin: CGPoint,
        viewport: CGSize
    ) -> (thumb: CGPoint, target: CGPoint, merge: Double)? {
        let targetJoint = 4 + 4 * (finger + 1)

        guard mergesThumbAndTarget,
              (8...20).contains(targetJoint),
              evidence.points[4].confidence >= Self.drawnConfidence,
              evidence.points[targetJoint].confidence >= Self.drawnConfidence else {
            return nil
        }

        let thumbTip = point(4, width: width, height: height, origin: origin)
        let targetTip = point(targetJoint, width: width, height: height, origin: origin)
        let gap = hypot(thumbTip.x - targetTip.x, thumbTip.y - targetTip.y)

        let merge = Self.mergeAmount(gap: gap, palm: palm)

        let thumb = fingertipCircleCenter(
            1, joint: 4, palm: palm,
            width: width, height: height, origin: origin, viewport: viewport
        )
        let target = fingertipCircleCenter(
            finger + 2, joint: targetJoint, palm: palm,
            width: width, height: height, origin: origin, viewport: viewport
        )

        return (thumb, target, merge)
    }

    /// Smoothstep from 0 at `mergeStartRatio` palms apart to 1 at `mergeEndRatio`.
    private static func mergeAmount(gap: CGFloat, palm: CGFloat) -> Double {
        let start = palm * mergeStartRatio
        let end = palm * mergeEndRatio

        guard start > end else {
            return gap <= end ? 1 : 0
        }

        let t = Double(min(1, max(0, (start - gap) / (start - end))))
        return t * t * (3 - 2 * t)
    }

    private func showsBubble(_ number: Int) -> Bool {
        switch exercise {
        case .opposition:
            return number == 1 || number == finger + 2
        case .extensionSequence:
            return number == finger + 2
        default:
            return true
        }
    }

    private func isActive(_ number: Int) -> Bool {
        guard guiding else {
            return false
        }
        if !exercise.isSequential {
            return true
        }
        return number == finger + 2 || number == 1 && exercise == .opposition
    }

    private func point(_ index: Int, width: Double, height: Double, origin: CGPoint) -> CGPoint {
        let p = evidence.points[index]
        return CGPoint(x: origin.x + (1 - p.x) * width, y: origin.y + (1 - p.y) * height)
    }
}
