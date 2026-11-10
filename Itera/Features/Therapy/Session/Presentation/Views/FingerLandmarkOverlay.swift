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
struct TMFingerLandmarkOverlay: View {
    let evidence: HandEvidence
    let progress: Double
    let exercise: FingerExercise
    let finger: Int
    let returning: Bool
    let showsTimer: Bool
    let guiding: Bool
    var completionID: UUID? = nil
    var onCompletionPresented: (UUID) -> Void = { _ in }

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
                context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: lineWidth)
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
                    context.stroke(line, with: .color(TherapyPalette.guidanceBlue), lineWidth: max(2, lineWidth - 1))
                }
            }
        }

        for index in evidence.points.indices where evidence.points[index].confidence >= 0.5 {
            let p = point(index, width: width, height: height, origin: origin)
            let dot = CGRect(x: p.x - dotRadius, y: p.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(TherapyPalette.guidanceYellow))
        }
    }

    @ViewBuilder
    private func circles(palm: CGFloat, width: Double, height: Double, origin: CGPoint, viewport: CGSize) -> some View {
        if usesWholeHandCircle {
            if let circle = handCircle(width: width, height: height, origin: origin, viewport: viewport) {
                TMTherapyGuideBubble(
                    progress: progress,
                    active: guiding,
                    completionID: completionID, onCompletionPresented: onCompletionPresented,
                    showsTimer: showsTimer,
                    diameter: circle.diameter, outlineOnly: true
                )
                .position(circle.center)
            }
        } else {
            ForEach(Array([4, 8, 12, 16, 20].enumerated()), id: \.offset) { index, joint in
                if showsBubble(index + 1) && evidence.points[joint].confidence >= 0.5 {
                    TMTherapyGuideBubble(
                        // No finger numbers: the instruction names the finger to move.
                        progress: progress,
                        active: isActive(index + 1),
                        completionID: isActive(index + 1) ? completionID : nil,
                        onCompletionPresented: onCompletionPresented,
                        showsTimer: showsTimer && isActive(index + 1),
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

    /// A padded circle around the hand, sized from the hand itself and kept fully on screen.
    private func handCircle(width: Double, height: Double, origin: CGPoint, viewport: CGSize) -> (center: CGPoint, diameter: CGFloat)? {
        guard let bounds = handBounds(width: width, height: height, origin: origin) else {
            return nil
        }
        // Keep the complete stroke inside the preview, including on smaller windows.
        let available = min(viewport.width, viewport.height) - 40
        guard available > 0 else {
            return nil
        }
        // Wide enough to enclose an open hand, never larger than before.
        let span = hypot(bounds.width, bounds.height)
        let diameter = Self.stepped(min(available * 0.75, max(100, span * 1.03)))
        let inset = diameter / 2 + 20
        let center = CGPoint(
            x: min(viewport.width - inset, max(inset, bounds.midX)),
            y: min(viewport.height - inset, max(inset, bounds.midY))
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

    private func point(_ index: Int, width: Double, height: Double, origin: CGPoint) -> CGPoint {
        let p = evidence.points[index]
        return CGPoint(x: origin.x + (1 - p.x) * width, y: origin.y + (1 - p.y) * height)
    }
}
