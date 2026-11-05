//
//  FingerLandmarkOverlay.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

/// Draws the tracked hand, its guide circles and one hold readout over the camera preview.
///
/// Sizes follow the hand's size on screen, so a hand farther from the camera gets smaller
/// circles. Text never sits on the hand: circles show only their progress ring, and the
/// remaining time appears once, beside the hand.
struct FingerLandmarkOverlay: View {
    let evidence: HandEvidence
    let progress: Double
    let remaining: Double
    let exercise: FingerExercise
    let finger: Int
    let returning: Bool
    let showsTimer: Bool
    let guiding: Bool
    var completionID: UUID? = nil
    var onCompletionPresented: (UUID) -> Void = { _ in }

    // MARK: - Sizing

    /// Fingertip circle diameters relative to the on-screen palm length (wrist to middle knuckle).
    private static let activeCircleRatio = 0.55
    private static let inactiveCircleRatio = 0.37
    private static let activeCircleRange: ClosedRange<CGFloat> = 48...108
    private static let inactiveCircleRange: ClosedRange<CGFloat> = 32...72
    /// Rounding step, so sizes do not shimmer with small tracking changes.
    private static let sizeStep: CGFloat = 4
    /// Palm length assumed when the wrist or middle knuckle is not visible.
    private static let fallbackPalm: CGFloat = 150

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / evidence.width, geometry.size.height / evidence.height)
            let width = evidence.width * scale
            let height = evidence.height * scale
            let origin = CGPoint(x: (geometry.size.width - width) / 2, y: (geometry.size.height - height) / 2)
            let palm = palmLength(width: width, height: height, origin: origin)

            Canvas { context, _ in
                drawSkeleton(in: &context, palm: palm, width: width, height: height, origin: origin, viewport: geometry.size)
            }

            circles(palm: palm, width: width, height: height, origin: origin, viewport: geometry.size)

            if showsTimer, let bounds = handBounds(width: width, height: height, origin: origin) {
                TherapyHoldReadout(remaining: remaining)
                    .position(readoutCenter(beside: bounds, gap: readoutGap(palm: palm), viewport: geometry.size))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    // MARK: - Drawing

    private func drawSkeleton(
        in context: inout GraphicsContext,
        palm: CGFloat,
        width: Double,
        height: Double,
        origin: CGPoint,
        viewport: CGSize
    ) {
        // Lines and joint dots thin out a little for a smaller, farther hand.
        let lineWidth = min(4, max(2, palm * 0.025))
        let dotRadius = min(5, max(3, palm * 0.03))

        for base in [1, 5, 9, 13, 17] {
            let chain = [0, base, base + 1, base + 2, base + 3]
            for pair in zip(chain, chain.dropFirst()) {
                guard evidence.points[pair.0].confidence >= 0.5,
                      evidence.points[pair.1].confidence >= 0.5 else { continue }
                var path = Path()
                path.move(to: point(pair.0, width: width, height: height, origin: origin))
                path.addLine(to: point(pair.1, width: width, height: height, origin: origin))
                context.stroke(path, with: .color(TherapyPalette.secondary), lineWidth: lineWidth)
            }
        }

        if !usesWholeHandCircle {
            for (index, joint) in [4, 8, 12, 16, 20].enumerated()
            where showsBubble(index + 1) && evidence.points[joint].confidence >= 0.5 {
                let anchor = point(joint, width: width, height: height, origin: origin)
                let center = fingertipCircleCenter(
                    index + 1, joint: joint, palm: palm,
                    width: width, height: height, origin: origin, viewport: viewport
                )
                if hypot(anchor.x - center.x, anchor.y - center.y) > 1 {
                    var line = Path()
                    line.move(to: anchor)
                    line.addLine(to: center)
                    context.stroke(line, with: .color(TherapyPalette.tertiary), lineWidth: max(2, lineWidth - 1))
                }
            }
        }

        for index in evidence.points.indices where evidence.points[index].confidence >= 0.5 {
            let p = point(index, width: width, height: height, origin: origin)
            let dot = CGRect(x: p.x - dotRadius, y: p.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(.white))
        }
    }

    @ViewBuilder
    private func circles(palm: CGFloat, width: Double, height: Double, origin: CGPoint, viewport: CGSize) -> some View {
        if usesWholeHandCircle {
            if let circle = handCircle(width: width, height: height, origin: origin, viewport: viewport) {
                TherapyGuideBubble(
                    label: "", remaining: remaining, progress: progress,
                    active: guiding, reached: completionID != nil,
                    completionID: completionID, onCompletionPresented: onCompletionPresented,
                    showsTimer: showsTimer, showsTimerText: false,
                    diameter: circle.diameter, outlineOnly: true
                )
                .position(circle.center)
            }
        } else {
            ForEach(Array([4, 8, 12, 16, 20].enumerated()), id: \.offset) { index, joint in
                if showsBubble(index + 1) && evidence.points[joint].confidence >= 0.5 {
                    TherapyGuideBubble(
                        // No finger numbers: the instruction names the finger to move.
                        label: "", remaining: remaining, progress: progress,
                        active: isActive(index + 1), reached: hasReached(index + 1),
                        completionID: isActive(index + 1) ? completionID : nil,
                        onCompletionPresented: onCompletionPresented,
                        showsTimer: showsTimer && isActive(index + 1),
                        showsTimerText: false,
                        diameter: fingertipDiameter(active: isActive(index + 1), palm: palm)
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

    /// On-screen distance from the wrist to the middle-finger knuckle: a steady size cue that
    /// barely changes while the fingers bend.
    private func palmLength(width: Double, height: Double, origin: CGPoint) -> CGFloat {
        guard evidence.points[0].confidence >= 0.5, evidence.points[9].confidence >= 0.5 else {
            return Self.fallbackPalm
        }

        let wrist = point(0, width: width, height: height, origin: origin)
        let knuckle = point(9, width: width, height: height, origin: origin)
        return hypot(wrist.x - knuckle.x, wrist.y - knuckle.y)
    }

    private func fingertipDiameter(active: Bool, palm: CGFloat) -> CGFloat {
        let ratio = active ? Self.activeCircleRatio : Self.inactiveCircleRatio
        let range = active ? Self.activeCircleRange : Self.inactiveCircleRange
        return Self.stepped(min(range.upperBound, max(range.lowerBound, palm * ratio)))
    }

    private static func stepped(_ value: CGFloat) -> CGFloat {
        (value / sizeStep).rounded() * sizeStep
    }

    /// The visible hand's bounding box in preview coordinates.
    private func handBounds(width: Double, height: Double, origin: CGPoint) -> CGRect? {
        let visible = evidence.points.indices
            .filter { evidence.points[$0].confidence >= 0.5 }
            .map { point($0, width: width, height: height, origin: origin) }

        guard let first = visible.first else {
            return nil
        }

        return visible.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, location in
            bounds.union(CGRect(origin: location, size: .zero))
        }
    }

    /// Clearance past the hand's outline: circles extend up to their radius beyond a fingertip.
    private func readoutGap(palm: CGFloat) -> CGFloat {
        guard !usesWholeHandCircle else {
            return 36
        }

        return fingertipDiameter(active: true, palm: palm) / 2 + 16
    }

    /// Beside the hand on whichever side has room, otherwise above or below it, always on screen.
    private func readoutCenter(beside hand: CGRect, gap: CGFloat, viewport: CGSize) -> CGPoint {
        let size = TherapyHoldReadout.size
        let margin: CGFloat = 16
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        let rightX = hand.maxX + gap + halfWidth
        let leftX = hand.minX - gap - halfWidth
        var center = CGPoint(x: rightX, y: hand.midY)

        if rightX + halfWidth > viewport.width - margin {
            center.x = leftX
        }
        if center.x - halfWidth < margin {
            // No room on either side: go above the hand, or below it near the top edge.
            center.x = hand.midX
            let above = hand.minY - gap - halfHeight
            center.y = above - halfHeight >= margin ? above : hand.maxY + gap + halfHeight
        }

        return CGPoint(
            x: min(viewport.width - margin - halfWidth, max(margin + halfWidth, center.x)),
            y: min(viewport.height - margin - halfHeight, max(margin + halfHeight, center.y))
        )
    }

    /// A padded circle around the hand, sized from the hand itself and kept fully on screen.
    private func handCircle(width: Double, height: Double, origin: CGPoint, viewport: CGSize) -> (center: CGPoint, diameter: CGFloat)? {
        let bases = [5, 9, 13, 17].filter { evidence.points[$0].confidence >= 0.5 }
        guard !bases.isEmpty, let bounds = handBounds(width: width, height: height, origin: origin) else {
            return nil
        }
        let palm = bases.reduce(CGPoint.zero) { sum, joint in
            let location = point(joint, width: width, height: height, origin: origin)
            return CGPoint(x: sum.x + location.x, y: sum.y + location.y)
        }
        let knuckles = CGPoint(x: palm.x / Double(bases.count), y: palm.y / Double(bases.count))
        let wrist = point(0, width: width, height: height, origin: origin)
        let anchor = CGPoint(x: knuckles.x + (knuckles.x - wrist.x) * 0.25, y: knuckles.y + (knuckles.y - wrist.y) * 0.25)
        // Keep the complete stroke inside the preview, including on smaller windows.
        let available = min(viewport.width, viewport.height) - 40
        guard available > 0 else {
            return nil
        }
        // Wide enough to enclose an open hand, never larger than before.
        let span = hypot(bounds.width, bounds.height)
        let diameter = Self.stepped(min(available * 0.75, max(140, span * 1.15)))
        let inset = diameter / 2 + 20
        let center = CGPoint(
            x: min(viewport.width - inset, max(inset, anchor.x)),
            y: min(viewport.height - inset, max(inset, anchor.y))
        )
        return (center, diameter)
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

    private func hasReached(_ number: Int) -> Bool {
        guard guiding else {
            return false
        }
        if !exercise.isSequential || number == 1 && exercise == .opposition {
            return completionID != nil
        }
        return number >= 2 && (number < finger + 2 || number == finger + 2 && completionID != nil)
    }

    private func point(_ index: Int, width: Double, height: Double, origin: CGPoint) -> CGPoint {
        let p = evidence.points[index]
        return CGPoint(x: origin.x + (1 - p.x) * width, y: origin.y + (1 - p.y) * height)
    }
}
