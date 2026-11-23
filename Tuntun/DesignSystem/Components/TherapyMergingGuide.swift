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
/// forms as they approach and the result settles into a single circle, so only one indicator
/// remains. With the `.midpoint` anchor both centres slide to their midpoint and the merged
/// circle grows a little; with `.second` the second circle stays put and the first slides into
/// it, so the merged circle is exactly the second one (a target whose drawn outline is its
/// acceptance boundary). The hold progress arc is a `TMTherapyGuideBubble` laid exactly on the
/// shader's outline, which keeps the bubble's completion acknowledgment. The caller decides
/// `merge` from its own geometry; changes are eased with a short spring, and Reduce Motion
/// applies them at once. The circles may also `glide`: their centres and sizes then ease between
/// tracking samples, so circles fed at the camera rate move at the display rate.
struct TMTherapyMergingGuide: View {
    enum Anchor {
        /// Both circles meet halfway and the merged circle grows slightly.
        case midpoint
        /// The second circle stays fixed; the first slides into it and takes its size.
        case second
        /// Neither circle moves or changes size; `merge` only widens the bridge, so a tracked
        /// point stays on the tracked point. The progress arc is drawn on the second circle only.
        case fixed
    }

    let first: CGPoint
    let second: CGPoint
    /// The second circle's diameter, and the first's unless `firstDiameter` is set.
    let diameter: CGFloat
    var firstDiameter: CGFloat? = nil
    /// 0 keeps two circles; 1 shows one merged circle.
    let merge: Double
    var anchor: Anchor = .midpoint
    let progress: Double
    /// False draws a quiet outline with no fill, for a target that is not the current one.
    let active: Bool
    var showsTimer = false
    var completionID: UUID? = nil
    var onCompletionPresented: (UUID) -> Void = { _ in }
    var tint: Color = TherapyPalette.guidanceOrange
    /// Plays the pop burst on the arc when a hold completes.
    var popsOnCompletion = false
    /// False drops the soft fill and keeps only the outline, for a circle drawn around
    /// something that must stay visible, such as the whole hand.
    var filled = true
    /// SF Symbols drawn at each circle's centre; the first fades out as the circles merge.
    var firstSymbol: String? = nil
    var secondSymbol: String? = nil
    /// How `merge` changes ease; pass a curve without bounce for a calmer indicator.
    var mergeAnimation: Animation = .spring(duration: 0.35, bounce: 0.15)
    /// Eases both centres and diameters toward each new value. Nil places them at once.
    var glide: Animation? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(reduceMotion ? nil : mergeAnimation, value: merge)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let glide {
            // Geometry is kept out of the layer's own animatable data, so callers without a
            // glide keep tracking their points exactly.
            GlidingLayer(
                guide: self,
                first: first,
                second: second,
                firstDiameter: firstDiameter ?? diameter,
                secondDiameter: diameter
            )
            .animation(reduceMotion ? nil : glide, value: first)
            .animation(reduceMotion ? nil : glide, value: second)
            .animation(reduceMotion ? nil : glide, value: diameter)
            .animation(reduceMotion ? nil : glide, value: firstDiameter)
        } else {
            layer(
                first: first,
                second: second,
                firstDiameter: firstDiameter ?? diameter,
                secondDiameter: diameter
            )
        }
    }

    fileprivate func layer(
        first: CGPoint,
        second: CGPoint,
        firstDiameter: CGFloat,
        secondDiameter: CGFloat
    ) -> some View {
        MergingGuideLayer(
            first: first,
            second: second,
            firstDiameter: firstDiameter,
            secondDiameter: secondDiameter,
            merge: min(1, max(0, merge)),
            anchor: anchor,
            progress: progress,
            active: active,
            showsTimer: showsTimer,
            completionID: completionID,
            onCompletionPresented: onCompletionPresented,
            tint: tint,
            popsOnCompletion: popsOnCompletion,
            filled: filled,
            firstSymbol: firstSymbol,
            secondSymbol: secondSymbol
        )
    }
}

extension TMTherapyMergingGuide {
    /// One circle in the same look, for a hold ring, a lone joint marker or a target without a
    /// tracked point.
    init(
        center: CGPoint,
        diameter: CGFloat,
        progress: Double = 0,
        active: Bool,
        showsTimer: Bool = false,
        completionID: UUID? = nil,
        onCompletionPresented: @escaping (UUID) -> Void = { _ in },
        tint: Color = TherapyPalette.guidanceOrange,
        popsOnCompletion: Bool = false,
        filled: Bool = true,
        symbol: String? = nil,
        glide: Animation? = nil
    ) {
        self.init(
            first: center,
            second: center,
            diameter: diameter,
            merge: 1,
            anchor: .second,
            progress: progress,
            active: active,
            showsTimer: showsTimer,
            completionID: completionID,
            onCompletionPresented: onCompletionPresented,
            tint: tint,
            popsOnCompletion: popsOnCompletion,
            filled: filled,
            secondSymbol: symbol,
            glide: glide
        )
    }
}

// MARK: - Gliding geometry

/// Interpolates both circles' centres and diameters frame by frame, then draws the layer at
/// the interpolated geometry.
private struct GlidingLayer: View, Animatable {
    let guide: TMTherapyMergingGuide
    var first: CGPoint
    var second: CGPoint
    var firstDiameter: CGFloat
    var secondDiameter: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(first.animatableData, second.animatableData),
                AnimatablePair(firstDiameter, secondDiameter)
            )
        }
        set {
            first.animatableData = newValue.first.first
            second.animatableData = newValue.first.second
            firstDiameter = newValue.second.first
            secondDiameter = newValue.second.second
        }
    }

    var body: some View {
        guide.layer(
            first: first,
            second: second,
            firstDiameter: firstDiameter,
            secondDiameter: secondDiameter
        )
    }
}

// MARK: - Layer

/// The animatable part: SwiftUI interpolates `merge` frame by frame for the shader.
private struct MergingGuideLayer: View, Animatable {
    let first: CGPoint
    let second: CGPoint
    let firstDiameter: CGFloat
    let secondDiameter: CGFloat
    var merge: Double
    let anchor: TMTherapyMergingGuide.Anchor
    let progress: Double
    let active: Bool
    let showsTimer: Bool
    let completionID: UUID?
    let onCompletionPresented: (UUID) -> Void
    let tint: Color
    let popsOnCompletion: Bool
    let filled: Bool
    let firstSymbol: String?
    let secondSymbol: String?

    var animatableData: Double {
        get { merge }
        set { merge = newValue }
    }

    /// With the midpoint anchor the merged circle grows a little, so joining reads as one
    /// combined target.
    private static let mergedGrowth = 0.12
    /// Bridge width as a fraction of the radius: almost none while apart, so distant circles
    /// stay cleanly separate, and a wide neck while merging.
    private static let separateSmoothing = 0.10
    private static let mergedSmoothing = 1.0
    /// Below this the two centres coincide on screen and one arc is drawn instead of two.
    private static let singleThreshold = 0.999

    /// Where the circles end up once merged.
    private var mergedCenter: CGPoint {
        switch anchor {
        case .midpoint:
            return CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        case .second, .fixed:
            return second
        }
    }

    private var mergedDiameter: CGFloat {
        switch anchor {
        case .midpoint:
            return max(firstDiameter, secondDiameter) * (1 + Self.mergedGrowth)
        case .second, .fixed:
            return secondDiameter
        }
    }

    /// Each centre slides toward the merged centre as the circles merge.
    private func shown(_ point: CGPoint) -> CGPoint {
        guard anchor != .fixed else {
            return point
        }

        let remaining = 1 - merge

        return CGPoint(
            x: mergedCenter.x + (point.x - mergedCenter.x) * remaining,
            y: mergedCenter.y + (point.y - mergedCenter.y) * remaining
        )
    }

    /// Each diameter eases toward the merged diameter as the circles merge.
    private func shown(_ diameter: CGFloat) -> CGFloat {
        guard anchor != .fixed else {
            return diameter
        }

        return diameter + (mergedDiameter - diameter) * merge
    }

    /// Bridge width for these shown circles.
    ///
    /// The smooth union grows the shape by up to a quarter of this width where the circles
    /// overlap, so it fades out as the centres come together: coincident circles (merged, or the
    /// single-circle form) keep exactly their radius, which the progress arc matches.
    private func smoothing(_ a: CGPoint, _ b: CGPoint, radius: CGFloat) -> CGFloat {
        guard radius > 0 else {
            return 0
        }

        let gap = hypot(a.x - b.x, a.y - b.y)
        let closeness = min(1, gap / radius)
        let width = Self.separateSmoothing + (Self.mergedSmoothing - Self.separateSmoothing) * merge

        return radius * width * closeness
    }

    /// Matches `TMTherapyGuideBubble`'s ring, so the progress arc covers the shader outline.
    private static func ringWidth(for diameter: CGFloat) -> CGFloat {
        min(14, max(6, diameter * 0.17))
    }

    var body: some View {
        let a = shown(first)
        let b = shown(second)
        let firstShownDiameter = shown(firstDiameter)
        let secondShownDiameter = shown(secondDiameter)
        // One outline width for the whole shape: the larger circle's, which carries the arc.
        let ringWidth = Self.ringWidth(for: max(firstShownDiameter, secondShownDiameter))
        let largerRadius = max(firstShownDiameter, secondShownDiameter) / 2
        let bridge = smoothing(a, b, radius: largerRadius)
        // Room for the ring, its underlay and the bridge's growth, so nothing is clipped square.
        let padding = largerRadius + bridge / 4 + ringWidth + 4
        let bounds = CGRect(
            x: min(a.x, b.x) - padding,
            y: min(a.y, b.y) - padding,
            width: abs(a.x - b.x) + padding * 2,
            height: abs(a.y - b.y) + padding * 2
        )

        ZStack(alignment: .topLeading) {
            shape(
                first: a,
                second: b,
                firstRadius: firstShownDiameter / 2,
                secondRadius: secondShownDiameter / 2,
                smoothing: bridge,
                ringWidth: ringWidth,
                bounds: bounds
            )

            ForEach(arcs(a, b, firstShownDiameter, secondShownDiameter), id: \.offset) { _, arc in
                TMTherapyGuideBubble(
                    progress: progress,
                    active: active,
                    completionID: completionID,
                    onCompletionPresented: onCompletionPresented,
                    showsTimer: showsTimer,
                    diameter: arc.diameter,
                    tint: tint,
                    drawsBackground: false,
                    popsOnCompletion: popsOnCompletion
                )
                .position(arc.center)
            }

            symbols(first: a, second: b)
        }
    }

    /// One arc once the circles have become one (always on the second with the fixed anchor),
    /// otherwise one per circle.
    private func arcs(
        _ a: CGPoint,
        _ b: CGPoint,
        _ firstShownDiameter: CGFloat,
        _ secondShownDiameter: CGFloat
    ) -> [(offset: Int, element: (center: CGPoint, diameter: CGFloat))] {
        let arcs = anchor == .fixed || merge >= Self.singleThreshold
            ? [(center: mergedCenter, diameter: mergedDiameter)]
            : [(center: a, diameter: firstShownDiameter), (center: b, diameter: secondShownDiameter)]

        return Array(arcs.enumerated()).map { ($0.offset, $0.element) }
    }

    @ViewBuilder
    private func symbols(first a: CGPoint, second b: CGPoint) -> some View {
        if let firstSymbol {
            symbol(firstSymbol, diameter: firstDiameter)
                .opacity(1 - merge)
                .position(a)
        }

        if let secondSymbol {
            symbol(secondSymbol, diameter: secondDiameter)
                .opacity(active ? 1 : 0.6)
                .position(b)
        }
    }

    /// A white glyph over a dark disc, so it reads on the tinted fill and on bright video.
    private func symbol(_ name: String, diameter: CGFloat) -> some View {
        let backing = min(64, max(36, diameter * 0.5))

        return Image(systemName: name)
            .typography(size: backing * 0.53, weight: .bold)
            .foregroundStyle(.white)
            .frame(width: backing, height: backing)
            .background(TherapyPalette.calmUnderlay, in: Circle())
    }

    private func shape(
        first a: CGPoint,
        second b: CGPoint,
        firstRadius: CGFloat,
        secondRadius: CGFloat,
        smoothing: CGFloat,
        ringWidth: CGFloat,
        bounds: CGRect
    ) -> some View {
        Rectangle()
            .fill(.black)
            .frame(width: bounds.width, height: bounds.height)
            .colorEffect(
                ShaderLibrary.mergingGuide(
                    .float2(Float(a.x - bounds.minX), Float(a.y - bounds.minY)),
                    .float2(Float(b.x - bounds.minX), Float(b.y - bounds.minY)),
                    .float(Float(firstRadius)),
                    .float(Float(secondRadius)),
                    .float(Float(smoothing)),
                    .float(Float(ringWidth)),
                    .color(tint),
                    // A quiet target keeps only a dimmer outline, so the current one stands out.
                    .float(active && filled ? 0.22 : 0),
                    .color(.white),
                    .float(active ? 0.85 : 0.5),
                    .color(.black),
                    .float(0.5)
                )
            )
            .offset(x: bounds.minX, y: bounds.minY)
    }
}
