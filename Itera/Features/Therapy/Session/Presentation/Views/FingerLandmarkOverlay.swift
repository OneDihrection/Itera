//
//  FingerLandmarkOverlay.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

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

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / evidence.width, geometry.size.height / evidence.height)
            let width = evidence.width * scale
            let height = evidence.height * scale
            let origin = CGPoint(x: (geometry.size.width - width) / 2, y: (geometry.size.height - height) / 2)
            Canvas { context, _ in
                for base in [1, 5, 9, 13, 17] {
                    let chain = [0, base, base + 1, base + 2, base + 3]
                    for pair in zip(chain, chain.dropFirst()) {
                        guard evidence.points[pair.0].confidence >= 0.5,
                              evidence.points[pair.1].confidence >= 0.5 else { continue }
                        var path = Path()
                        path.move(to: point(pair.0, width: width, height: height, origin: origin))
                        path.addLine(to: point(pair.1, width: width, height: height, origin: origin))
                        context.stroke(path, with: .color(TherapyPalette.secondary), lineWidth: 4)
                    }
                }
                if !usesWholeHandCircle {
                    for (index, joint) in [4, 8, 12, 16, 20].enumerated()
                    where showsBubble(index + 1) && evidence.points[joint].confidence >= 0.5 {
                        let anchor = point(joint, width: width, height: height, origin: origin)
                        let center = fingertipCircleCenter(index + 1, joint: joint, width: width, height: height, origin: origin, viewport: geometry.size)
                        if hypot(anchor.x - center.x, anchor.y - center.y) > 1 {
                            var line = Path()
                            line.move(to: anchor)
                            line.addLine(to: center)
                            context.stroke(line, with: .color(TherapyPalette.tertiary), lineWidth: 3)
                        }
                    }
                }
                for index in evidence.points.indices where evidence.points[index].confidence >= 0.5 {
                    let p = point(index, width: width, height: height, origin: origin)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                }
            }
            if usesWholeHandCircle {
                if let circle = handCircle(width: width, height: height, origin: origin, viewport: geometry.size) {
                    TherapyGuideBubble(
                        label: "", remaining: remaining, progress: progress,
                        active: guiding, reached: completionID != nil,
                        completionID: completionID, onCompletionPresented: onCompletionPresented,
                        showsTimer: showsTimer, diameter: circle.diameter, outlineOnly: true
                    )
                    .position(circle.center)
                }
            } else {
                ForEach(Array([4, 8, 12, 16, 20].enumerated()), id: \.offset) { index, joint in
                    if showsBubble(index + 1) && evidence.points[joint].confidence >= 0.5 {
                        TherapyGuideBubble(
                            label: String(index + 1), remaining: remaining, progress: progress,
                            active: isActive(index + 1), reached: hasReached(index + 1),
                            completionID: isActive(index + 1) ? completionID : nil,
                            onCompletionPresented: onCompletionPresented,
                            showsTimer: showsTimer && isActive(index + 1)
                        )
                        .position(fingertipCircleCenter(index + 1, joint: joint, width: width, height: height, origin: origin, viewport: geometry.size))
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private var usesWholeHandCircle: Bool {
        exercise == .fullFist || exercise == .hookFist
    }

    /// A padded enclosing circle, in the same mirrored aspect-fit space as the preview.
    private func handCircle(width: Double, height: Double, origin: CGPoint, viewport: CGSize) -> (center: CGPoint, diameter: CGFloat)? {
        let bases = [5, 9, 13, 17].filter { evidence.points[$0].confidence >= 0.5 }
        guard !bases.isEmpty else {
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
        let diameter = available * 0.75
        let inset = diameter / 2 + 20
        let center = CGPoint(
            x: min(viewport.width - inset, max(inset, anchor.x)),
            y: min(viewport.height - inset, max(inset, anchor.y))
        )
        return (center, diameter)
    }

    private func fingertipCircleCenter(_ number: Int, joint: Int, width: Double, height: Double, origin: CGPoint, viewport: CGSize) -> CGPoint {
        let anchor = point(joint, width: width, height: height, origin: origin)
        let radius: CGFloat = isActive(number) ? 54 : 36
        let horizontalInset = min(radius + 10, viewport.width / 2)
        let verticalInset = min(radius + 40, viewport.height / 2)
        return CGPoint(
            x: min(viewport.width - horizontalInset, max(horizontalInset, anchor.x)),
            y: min(viewport.height - verticalInset, max(verticalInset, anchor.y))
        )
    }

    private func showsBubble(_ number: Int) -> Bool {
        guard exercise == .opposition else {
            return true
        }
        return number == 1 || number == finger + 2
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
