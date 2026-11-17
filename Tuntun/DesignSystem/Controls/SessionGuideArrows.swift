//
//  SessionGuideArrows.swift
//  Tuntun
//
//  Created by dimaswisodewo on 17/11/2026.
//
// Drawing moved unchanged from SessionTargetOverlay.swift (removed 2026-11-17), itself adapted
// from VisionPoc/SessionTargetOverlay.swift.

import SwiftUI

/// Which way to move a limb when there is no bubble yet, such as while a target is calibrated.
///
/// The cue is a fixed path from `tail` (the limb's start, fixed to the body) to `tip`; the limb
/// moves along it rather than the cue following the limb.
struct SessionMovementCue {
    let tail: CGPoint
    let tip: CGPoint
    /// The joint the limb turns around; nil draws a gentle bow from `tail` to `tip`.
    var pivot: CGPoint? = nil
    /// The tracked joint; the stretch of the path it has already passed fades out.
    var joint: CGPoint? = nil
}

/// A reach direction drawn from the start, kept visible at the image edge.
struct SessionReachArrow {
    let origin: CGPoint
    let tip: CGPoint
}

/// The body exercises' guidance arrows, in normalized image coordinates: one solid curved arrow
/// from the joint to the active bubble (hidden once the joint arrives or a hold begins), the
/// calibration cue along a fixed path, and the reach direction.
///
/// A brighter stretch travels toward each open chevron tip every 1.5 s, still and full strength
/// under Reduce Motion. Every stroke lies over a dark underlay so it reads at 2.5 m. It takes
/// values only; the bubbles and joint are drawn by `TMSessionBubbleOverlay` on top.
struct TMSessionGuideArrows: View {
    let imageAspect: Double
    /// The arrow to the active bubble; nil draws none.
    let approach: SessionBubbleGuide?
    var settingUp = false
    /// Drawn at full strength whatever the stage, because it guides calibration.
    var movementCue: SessionMovementCue? = nil
    var reachArrow: SessionReachArrow? = nil
    let mirrored: Bool

    /// The calibration cue's last shape and when it last appeared or went away, kept so it can
    /// fade out after the caller drops it. A reference, so updating it while drawing never
    /// invalidates the view.
    private final class CueMemory {
        var cue: SessionMovementCue?
        var changedAt = Date.distantPast
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cueMemory = CueMemory()

    private let arrowSweepPeriod = 1.5
    private let cueFadeDuration = 0.25

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            canvas(now: timeline.date)
        }
        .onChange(of: movementCue != nil) {
            trackCueVisibility()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func canvas(now: Date) -> some View {
        Canvas { context, size in
            guard imageAspect > 0 else {
                return
            }

            let geometry = CameraDisplayGeometry(aspect: imageAspect, viewport: size)
            let scale = geometry.imageRect.height
            let imageBounds = geometry.imageRect
            func point(_ point: CGPoint) -> CGPoint {
                geometry.point(point, mirrored: mirrored)
            }

            if let reachArrow {
                drawReachDirection(
                    from: point(reachArrow.origin),
                    to: point(reachArrow.tip),
                    bounds: imageBounds,
                    now: now,
                    context: &context
                )
            }

            // The saved start is only a reference during reach capture, never a destination.
            // Once a hold has begun, the hold arc is the only active cue.
            if let guide = approach,
               !settingUp,
               !guide.trackedJointInside,
               guide.dwellProgress == 0,
               let tracked = guide.trackedJoint {
                drawDirection(
                    from: point(tracked),
                    to: point(guide.activeZone == .start ? guide.startCenter : guide.targetCenter),
                    radius: guide.radius * scale,
                    pivot: guide.pivot.map(point),
                    bounds: imageBounds,
                    now: now,
                    context: &context
                )
            }

            // The calibration arrow is a fixed path the joint moves along, under the circles.
            if let cue = movementCue ?? cueMemory.cue {
                cueMemory.cue = cue

                // Start just outside the saved start bubble when one is drawn.
                let gap = approach.map { $0.radius * scale + 6 } ?? 26

                drawCurvedArrow(
                    from: point(cue.tail),
                    to: point(cue.tip),
                    pivot: cue.pivot.map(point),
                    trimStart: gap,
                    trimEnd: 0,
                    minimumVisible: Self.cueMinimumLength,
                    passed: cue.joint.map(point),
                    fade: cueOpacity(at: now),
                    bounds: imageBounds,
                    now: now,
                    context: &context
                )
            }
        }
    }

    /// 0...1 for the calibration cue: it fades in after appearing and out after going away, so a
    /// cue that comes and goes never flashes. Under Reduce Motion it shows or hides at once.
    private func cueOpacity(at now: Date) -> Double {
        let visible = movementCue != nil

        guard !reduceMotion else {
            return visible ? 1 : 0
        }

        let progress = min(1, max(0, now.timeIntervalSince(cueMemory.changedAt) / cueFadeDuration))

        return visible ? progress : 1 - progress
    }

    /// Restarts the fade from the cue's current opacity, so a quick hide-and-show never jumps.
    /// The opacity before the change is the fade's progress p (going away) or 1 − p (appearing);
    /// either way the new fade must start at progress 1 − p.
    private func trackCueVisibility() {
        let now = Date()

        guard !reduceMotion else {
            cueMemory.changedAt = now
            return
        }

        let progress = min(1, max(0, now.timeIntervalSince(cueMemory.changedAt) / cueFadeDuration))

        cueMemory.changedAt = now.addingTimeInterval(-(1 - progress) * cueFadeDuration)
    }

    // MARK: - Drawing
    //
    // Every shape is drawn twice: a wider dark underlay, then the colored stroke. The underlay keeps
    // the guidance readable at 2.5 m on any camera image, and nothing here fades while it is needed.

    /// Strokes `path` with a dark underlay under the colored line.
    private func strokeWithUnderlay(
        _ path: Path, color: Color, width: Double, style: StrokeStyle? = nil, context: inout GraphicsContext
    ) {
        var under = style ?? StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        var line = style ?? StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        under.lineWidth = width + 7
        line.lineWidth = width

        context.stroke(path, with: .color(TherapyPalette.calmUnderlay), style: under)
        context.stroke(path, with: .color(color), style: line)
    }

    /// Keep the direction cue visible at the image edge without changing measured coordinates.
    private func drawReachDirection(
        from origin: CGPoint, to tip: CGPoint, bounds: CGRect, now: Date, context: inout GraphicsContext
    ) {
        let distance = hypot(tip.x - origin.x, tip.y - origin.y)
        guard distance > 0, bounds.width > 64, bounds.height > 64 else { return }
        let dx = (tip.x - origin.x) / distance
        let dy = (tip.y - origin.y) / distance
        let length = min(max(distance, 120), min(bounds.width, bounds.height) * 0.35)
        let inset = bounds.insetBy(dx: 24, dy: 24)
        let tail = CGPoint(
            x: min(max(origin.x, inset.minX + max(0, -dx * length)), inset.maxX - max(0, dx * length)),
            y: min(max(origin.y, inset.minY + max(0, -dy * length)), inset.maxY - max(0, dy * length))
        )
        let head = CGPoint(x: tail.x + dx * length, y: tail.y + dy * length)

        drawCurvedArrow(
            from: tail,
            to: head,
            pivot: nil,
            trimStart: 0,
            trimEnd: 0,
            fade: 1,
            bounds: bounds,
            now: now,
            context: &context
        )
    }

    /// One arrow from the joint to the active bubble. It keeps full strength while the joint is
    /// outside the bubble and is not drawn once the joint arrives.
    private func drawDirection(
        from joint: CGPoint,
        to center: CGPoint,
        radius: Double,
        pivot: CGPoint?,
        bounds: CGRect,
        now: Date,
        context: inout GraphicsContext
    ) {
        let distance = hypot(center.x - joint.x, center.y - joint.y)
        let available = distance - radius - 20

        guard available > 4 else {
            return
        }

        // The arrow fades over the last stretch so it leaves quietly as the joint arrives.
        let fade = min(1, max(0, (available - 4) / 60))

        drawCurvedArrow(
            from: joint,
            to: center,
            pivot: pivot,
            trimStart: 26,
            trimEnd: radius + 14,
            fade: fade,
            bounds: bounds,
            now: now,
            context: &context
        )
    }

    // MARK: - Curved arrow

    /// How far the chevron tip's arms reach back along the shaft and out to each side, in points.
    private static let arrowHeadLength = 16.0
    private static let arrowHeadHalfWidth = 14.0
    /// Shaft and underlay widths, in points.
    private static let arrowShaftWidth = 6.0
    private static let arrowUnderlayWidth = 11.0
    /// Longest turn a lengthened calibration arrow may sweep around its pivot.
    private static let maximumCueSweep = 150 * Double.pi / 180
    /// How far a pivot-less arrow bows out at its middle, as a fraction of its chord.
    private static let arrowBowFraction = 0.35
    /// How far an arrow around a pivot bulges outward at its middle, as a fraction of its chord,
    /// so even a short turn reads as a swing rather than a straight line.
    private static let arrowPivotBulgeFraction = 0.15

    /// One curved arrow from `tail` to `tip`: a solid shaft that follows the limb's turn around
    /// `pivot` (or bows without one) and an open chevron tip.
    ///
    /// The shaft rests at reduced strength while a brighter stretch travels toward the head every
    /// `arrowSweepPeriod`; under Reduce Motion the shaft is full strength and still. `trimStart`
    /// and `trimEnd` keep the arrow clear of the joint and of the bubble it points at, cut at the
    /// exact crossing so the arrow slides smoothly as the joint moves. A positive
    /// `minimumVisible` lengthens a short arrow in the same direction, so at least that much shows
    /// beyond `trimStart`; arrows that must end at a bubble pass zero. A fixed arrow that a joint
    /// moves along passes that joint as `passed`: the shaft behind it fades and the travelling
    /// highlight runs only ahead of it.
    private func drawCurvedArrow(
        from tail: CGPoint,
        to tip: CGPoint,
        pivot: CGPoint?,
        trimStart: Double,
        trimEnd: Double,
        minimumVisible: Double = 0,
        passed: CGPoint? = nil,
        fade: Double,
        bounds: CGRect,
        now: Date,
        context: inout GraphicsContext
    ) {
        guard fade > 0,
              let points = guidePoints(
                  from: tail,
                  to: tip,
                  pivot: pivot,
                  trimStart: trimStart,
                  trimEnd: trimEnd,
                  minimumVisible: minimumVisible,
                  bounds: bounds
              ),
              let point = points.last else {
            return
        }

        // The tangent is taken about 8 pt back so one short last step cannot twist the head.
        let before = points.last { hypot(point.x - $0.x, point.y - $0.y) >= 8 } ?? points[0]
        let tangentLength = hypot(point.x - before.x, point.y - before.y)

        guard tangentLength > 0 else {
            return
        }

        let direction = CGPoint(
            x: (point.x - before.x) / tangentLength,
            y: (point.y - before.y) / tangentLength
        )

        // The shaft runs into the chevron's point; stopping half a stroke short keeps its round cap
        // inside the point instead of poking past it.
        let shaftPoints = trimmed(
            Array(points.reversed()),
            outside: point,
            radius: Self.arrowShaftWidth / 2
        ).map { Array($0.reversed()) } ?? []
        var shaft = Path()

        if let first = shaftPoints.first {
            shaft.move(to: first)
            shaftPoints.dropFirst().forEach { shaft.addLine(to: $0) }
        }

        let head = arrowHead(at: point, direction: direction)
        let round = StrokeStyle(lineWidth: Self.arrowUnderlayWidth, lineCap: .round, lineJoin: .round)

        // The part of the shaft the joint has already moved past, as a fraction of its length.
        let behind = passed.map { arcFraction(of: $0, along: shaftPoints) } ?? 0
        let ahead = shaft.trimmedPath(from: behind, to: 1)

        if behind > 0 {
            context.drawLayer { layer in
                layer.opacity = fade * Self.passedShaftOpacity
                drawShaft(shaft.trimmedPath(from: 0, to: behind), round: round, layer: &layer)
            }
        }

        context.drawLayer { layer in
            layer.opacity = fade

            layer.stroke(ahead, with: .color(TherapyPalette.calmUnderlay), style: round)
            layer.stroke(head, with: .color(TherapyPalette.calmUnderlay), style: round)

            var line = round
            line.lineWidth = Self.arrowShaftWidth
            layer.stroke(ahead, with: .color(.white.opacity(reduceMotion ? 1 : 0.55)), style: line)

            if !reduceMotion {
                // A stretch a quarter of the shaft long enters at the tail (or the joint) and leaves
                // at the head.
                let front = (now.timeIntervalSinceReferenceDate / arrowSweepPeriod)
                    .truncatingRemainder(dividingBy: 1) * 1.25
                let highlight = ahead.trimmedPath(from: max(0, front - 0.25), to: min(1, front))
                layer.stroke(highlight, with: .color(.white), style: line)
            }

            // The chevron stays full strength, so the direction reads even between sweeps.
            layer.stroke(head, with: .color(.white), style: line)
        }
    }

    /// Strokes a shaft stretch with its dark underlay under a full-strength white line.
    private func drawShaft(_ path: Path, round: StrokeStyle, layer: inout GraphicsContext) {
        var line = round
        line.lineWidth = Self.arrowShaftWidth

        layer.stroke(path, with: .color(TherapyPalette.calmUnderlay), style: round)
        layer.stroke(path, with: .color(.white), style: line)
    }

    /// How far along the polyline, by arc length, the point nearest to `point` lies, 0...1.
    private func arcFraction(of point: CGPoint, along line: [CGPoint]) -> Double {
        let total = polylineLength(line)

        guard line.count > 1, total > 0 else {
            return 0
        }

        var walked = 0.0
        var best = (distance: Double.infinity, arc: 0.0)

        for index in 1..<line.count {
            let start = line[index - 1]
            let end = line[index]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let segment = hypot(dx, dy)
            let t = segment > 0
                ? min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (segment * segment)))
                : 0
            let distance = hypot(point.x - (start.x + dx * t), point.y - (start.y + dy * t))

            if distance < best.distance {
                best = (distance, walked + segment * t)
            }

            walked += segment
        }

        return best.arc / total
    }

    /// The arrow's centre line: lengthened to `minimumVisible` when
    /// positive, curved around `pivot` or bowed, and trimmed clear of the tail and the end. Nil when
    /// too little would show.
    private func guidePoints(
        from tail: CGPoint,
        to tip: CGPoint,
        pivot: CGPoint?,
        trimStart: Double,
        trimEnd: Double,
        minimumVisible: Double,
        bounds: CGRect
    ) -> [CGPoint]? {
        let end = minimumVisible > 0
            ? extendedTip(from: tail, to: tip, pivot: pivot, trim: trimStart, visible: minimumVisible)
            : tip
        let curve = curvePoints(from: tail, to: end, pivot: pivot, bounds: bounds)

        // The end is trimmed by trimming the reversed curve from its start.
        guard let afterTail = trimmed(curve, outside: tail, radius: trimStart),
              let beforeEnd = trimmed(Array(afterTail.reversed()), outside: end, radius: trimEnd) else {
            return nil
        }

        let points = Array(beforeEnd.reversed())

        guard polylineLength(points) >= 30 else {
            return nil
        }

        return points
    }

    // MARK: - Calibration cue

    /// Shortest calibration arrow shown beyond its start, in points; a shorter cue is lengthened
    /// along its turn.
    private static let cueMinimumLength = 160.0
    /// Strength of the stretch of the calibration arrow the joint has already passed.
    private static let passedShaftOpacity = 0.2

    /// Whether the arrow can turn around `pivot`: both ends must sit clearly away from it.
    private func usesPivot(_ pivot: CGPoint?, tail: CGPoint, tip: CGPoint) -> Bool {
        guard let pivot else {
            return false
        }

        return hypot(tail.x - pivot.x, tail.y - pivot.y) > 20
            && hypot(tip.x - pivot.x, tip.y - pivot.y) > 20
    }

    /// The tip of an arrow that shows at least `visible` beyond the circle of radius `trim` around
    /// the tail, in the same direction as `tip`. Around a pivot the turn keeps its sense and the
    /// tail's radius, up to `maximumCueSweep`; a bow moves the tip straight out. A long enough
    /// arrow keeps its tip.
    private func extendedTip(
        from tail: CGPoint,
        to tip: CGPoint,
        pivot: CGPoint?,
        trim: Double,
        visible: Double
    ) -> CGPoint {
        let length = trim + visible

        if let pivot, usesPivot(pivot, tail: tail, tip: tip) {
            let radius = hypot(tail.x - pivot.x, tail.y - pivot.y)
            let startAngle = atan2(tail.y - pivot.y, tail.x - pivot.x)
            let sweep = shortestSweep(from: startAngle, to: atan2(tip.y - pivot.y, tip.x - pivot.x))
            let tipRadius = hypot(tip.x - pivot.x, tip.y - pivot.y)

            guard abs(sweep) > 0.01,
                  abs(sweep) * (radius + tipRadius) / 2 < length else {
                return tip
            }

            // The trim circle cuts the arc where its chord from the tail equals `trim`, so it
            // removes slightly more arc than `trim` itself.
            let trimmedTurn = trim < 2 * radius
                ? 2 * asin(trim / (2 * radius))
                : Self.maximumCueSweep
            let turn = min(Self.maximumCueSweep, trimmedTurn + visible / radius) * (sweep > 0 ? 1 : -1)

            return CGPoint(
                x: pivot.x + cos(startAngle + turn) * radius,
                y: pivot.y + sin(startAngle + turn) * radius
            )
        }

        let chord = hypot(tip.x - tail.x, tip.y - tail.y)

        guard chord > 0, chord < length else {
            return tip
        }

        return CGPoint(
            x: tail.x + (tip.x - tail.x) / chord * length,
            y: tail.y + (tip.y - tail.y) / chord * length
        )
    }

    /// The signed turn from one angle to another, the shorter way round.
    private func shortestSweep(from start: Double, to end: Double) -> Double {
        var sweep = end - start

        if sweep > .pi {
            sweep -= 2 * .pi
        } else if sweep < -.pi {
            sweep += 2 * .pi
        }

        return sweep
    }

    /// The polyline from where it first leaves the circle around `center`, starting with the exact
    /// crossing point; nil when it never leaves the circle.
    private func trimmed(_ points: [CGPoint], outside center: CGPoint, radius: Double) -> [CGPoint]? {
        guard let first = points.first else {
            return nil
        }

        guard radius > 0, hypot(first.x - center.x, first.y - center.y) < radius else {
            return points
        }

        for index in points.indices.dropFirst() {
            let previous = points[index - 1]
            let current = points[index]
            let before = hypot(previous.x - center.x, previous.y - center.y)
            let after = hypot(current.x - center.x, current.y - center.y)

            guard after >= radius else {
                continue
            }

            // Distance to the center changes almost linearly over one short sample step.
            let t = (radius - before) / max(after - before, 0.0001)
            let crossing = CGPoint(
                x: previous.x + (current.x - previous.x) * t,
                y: previous.y + (current.y - previous.y) * t
            )

            return [crossing] + points[index...]
        }

        return nil
    }

    /// Samples the arrow's path. Around a pivot it sweeps the shorter way between the tail and tip
    /// angles while its radius blends between theirs and bulges outward in the middle, so it still
    /// ends exactly at the tip. Without a usable pivot it bows: upward for a mostly sideways arrow,
    /// otherwise away from the image's vertical center line. The side depends on direction rather
    /// than position near the center, so joint jitter cannot flip it.
    private func curvePoints(
        from tail: CGPoint,
        to tip: CGPoint,
        pivot: CGPoint?,
        bounds: CGRect
    ) -> [CGPoint] {
        let samples = 32

        if let pivot, usesPivot(pivot, tail: tail, tip: tip) {
            let startAngle = atan2(tail.y - pivot.y, tail.x - pivot.x)
            let sweep = shortestSweep(from: startAngle, to: atan2(tip.y - pivot.y, tip.x - pivot.x))
            let startRadius = hypot(tail.x - pivot.x, tail.y - pivot.y)
            let endRadius = hypot(tip.x - pivot.x, tip.y - pivot.y)
            let bulge = hypot(tip.x - tail.x, tip.y - tail.y) * Self.arrowPivotBulgeFraction

            return (0...samples).map { index in
                let t = Double(index) / Double(samples)
                let angle = startAngle + sweep * t
                let radius = startRadius
                    + (endRadius - startRadius) * t
                    + bulge * sin(.pi * t)

                return CGPoint(x: pivot.x + cos(angle) * radius, y: pivot.y + sin(angle) * radius)
            }
        }

        let chord = hypot(tip.x - tail.x, tip.y - tail.y)

        guard chord > 0 else {
            return [tail, tip]
        }

        let middle = CGPoint(x: (tail.x + tip.x) / 2, y: (tail.y + tip.y) / 2)
        var normal = CGPoint(x: -(tip.y - tail.y) / chord, y: (tip.x - tail.x) / chord)
        let sideways = abs(tip.x - tail.x) >= abs(tip.y - tail.y)
        let flip = sideways
            ? normal.y > 0
            : (tail.x - bounds.midX) * normal.x < 0

        if flip {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }

        // A quadratic curve's midpoint lies halfway to its control point, so the control sits at
        // twice the wanted bulge.
        let offset = chord * Self.arrowBowFraction * 2
        let control = CGPoint(x: middle.x + normal.x * offset, y: middle.y + normal.y * offset)

        return (0...samples).map { index in
            let t = Double(index) / Double(samples)
            let u = 1 - t

            return CGPoint(
                x: u * u * tail.x + 2 * u * t * control.x + t * t * tip.x,
                y: u * u * tail.y + 2 * u * t * control.y + t * t * tip.y
            )
        }
    }

    private func polylineLength(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }

    /// An open chevron whose point is `end`, aligned with `direction`, stroked like the shaft.
    private func arrowHead(at end: CGPoint, direction: CGPoint) -> Path {
        let base = CGPoint(
            x: end.x - direction.x * Self.arrowHeadLength,
            y: end.y - direction.y * Self.arrowHeadLength
        )
        let side = CGPoint(
            x: -direction.y * Self.arrowHeadHalfWidth,
            y: direction.x * Self.arrowHeadHalfWidth
        )

        var head = Path()
        head.move(to: CGPoint(x: base.x + side.x, y: base.y + side.y))
        head.addLine(to: end)
        head.addLine(to: CGPoint(x: base.x - side.x, y: base.y - side.y))

        return head
    }
}
