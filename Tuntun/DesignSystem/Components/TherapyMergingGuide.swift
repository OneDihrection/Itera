//
//  TherapyMergingGuide.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 17/11/2026.
//

import SwiftUI

/// Two guide circles that flow together into one as `merge` goes from 0 to 1.
///
/// The `mergingGuide` Metal shader draws both circles as one gooey shape: a rounded bridge
/// forms as they approach, the centres slide to their midpoint and the result settles into a
/// single, slightly larger circle, so only one indicator remains. The hold progress arc is a
/// `TMTherapyGuideBubble` laid exactly on the shader's outline, which keeps the bubble's
/// completion acknowledgment. The caller decides `merge` from its own geometry; changes are
/// eased with a short spring, and Reduce Motion applies them at once.
struct TMTherapyMergingGuide: View {
    let first: CGPoint
    let second: CGPoint
    let diameter: CGFloat
    /// 0 keeps two circles; 1 shows one merged circle at the midpoint.
    let merge: Double
    let progress: Double
    let active: Bool
    var showsTimer = false
    var completionID: UUID? = nil
    var onCompletionPresented: (UUID) -> Void = { _ in }
    var tint: Color = TherapyPalette.guidanceOrange
    /// Plays the pop burst on the arc when a hold completes.
    var popsOnCompletion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MergingGuideLayer(
            first: first,
            second: second,
            diameter: diameter,
            merge: min(1, max(0, merge)),
            progress: progress,
            active: active,
            showsTimer: showsTimer,
            completionID: completionID,
            onCompletionPresented: onCompletionPresented,
            tint: tint,
            popsOnCompletion: popsOnCompletion
        )
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15), value: merge)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Layer

/// The animatable part: SwiftUI interpolates `merge` frame by frame for the shader.
private struct MergingGuideLayer: View, Animatable {
    let first: CGPoint
    let second: CGPoint
    let diameter: CGFloat
    var merge: Double
    let progress: Double
    let active: Bool
    let showsTimer: Bool
    let completionID: UUID?
    let onCompletionPresented: (UUID) -> Void
    let tint: Color
    let popsOnCompletion: Bool

    var animatableData: Double {
        get { merge }
        set { merge = newValue }
    }

    /// The merged circle grows a little, so joining reads as one combined target.
    private static let mergedGrowth = 0.12
    /// Bridge width as a fraction of the radius: almost none while apart, so distant circles
    /// stay cleanly separate, and a wide neck while merging.
    private static let separateSmoothing = 0.10
    private static let mergedSmoothing = 1.0
    /// Below this the two centres coincide on screen and one arc is drawn instead of two.
    private static let singleThreshold = 0.999

    private var midpoint: CGPoint {
        CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    /// Each centre slides toward the midpoint as the circles merge.
    private func shown(_ point: CGPoint) -> CGPoint {
        let remaining = 1 - merge

        return CGPoint(
            x: midpoint.x + (point.x - midpoint.x) * remaining,
            y: midpoint.y + (point.y - midpoint.y) * remaining
        )
    }

    private var shownDiameter: CGFloat {
        diameter * (1 + Self.mergedGrowth * merge)
    }

    /// Matches `TMTherapyGuideBubble`'s ring, so the progress arc covers the shader outline.
    private var ringWidth: CGFloat {
        min(14, max(6, shownDiameter * 0.17))
    }

    var body: some View {
        let a = shown(first)
        let b = shown(second)
        let radius = shownDiameter / 2
        let padding = radius + ringWidth + 4
        let bounds = CGRect(
            x: min(a.x, b.x) - padding,
            y: min(a.y, b.y) - padding,
            width: abs(a.x - b.x) + padding * 2,
            height: abs(a.y - b.y) + padding * 2
        )

        ZStack(alignment: .topLeading) {
            shape(first: a, second: b, radius: radius, bounds: bounds)

            ForEach(arcCenters(a, b), id: \.offset) { _, center in
                TMTherapyGuideBubble(
                    progress: progress,
                    active: active,
                    completionID: completionID,
                    onCompletionPresented: onCompletionPresented,
                    showsTimer: showsTimer,
                    diameter: shownDiameter,
                    tint: tint,
                    drawsBackground: false,
                    popsOnCompletion: popsOnCompletion
                )
                .position(center)
            }
        }
    }

    /// One arc once the circles have become one, otherwise one per circle.
    private func arcCenters(_ a: CGPoint, _ b: CGPoint) -> [(offset: Int, element: CGPoint)] {
        let centers = merge >= Self.singleThreshold ? [midpoint] : [a, b]
        return Array(centers.enumerated()).map { ($0.offset, $0.element) }
    }

    private func shape(first a: CGPoint, second b: CGPoint, radius: CGFloat, bounds: CGRect) -> some View {
        let smoothing = radius * (Self.separateSmoothing + (Self.mergedSmoothing - Self.separateSmoothing) * merge)

        return Rectangle()
            .fill(.black)
            .frame(width: bounds.width, height: bounds.height)
            .colorEffect(
                ShaderLibrary.mergingGuide(
                    .float2(Float(a.x - bounds.minX), Float(a.y - bounds.minY)),
                    .float2(Float(b.x - bounds.minX), Float(b.y - bounds.minY)),
                    .float(Float(radius)),
                    .float(Float(smoothing)),
                    .float(Float(ringWidth)),
                    .color(active ? tint : .white),
                    .float(active ? 0.22 : 0.9),
                    .color(.white),
                    .float(active ? 0.85 : 0),
                    .color(.black),
                    .float(0.5)
                )
            )
            .offset(x: bounds.minX, y: bounds.minY)
    }
}
