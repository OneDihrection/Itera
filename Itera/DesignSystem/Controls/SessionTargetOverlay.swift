//
//  SessionTargetOverlay.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//
// Drawing adapted from VisionPoc/SessionTargetOverlay.swift.

import SwiftUI

struct SessionBubbleGuide {
    enum Zone { case start, target }
    let startCenter: CGPoint
    let targetCenter: CGPoint
    let trackedJoint: CGPoint?
    let radius: Double
    let activeZone: Zone
    let trackedJointInside: Bool
    let dwellProgress: Double
    /// The joint the limb turns around, such as the shoulder for an arm raise. When set, the arrow
    /// to the active bubble follows that turn instead of a gentle bow.
    var pivot: CGPoint? = nil
}

/// Which way to move a limb when there is no bubble yet, such as while a target is calibrated.
struct SessionMovementCue {
    let tail: CGPoint
    let tip: CGPoint
    /// The joint the limb turns around; nil draws a gentle bow from `tail` to `tip`.
    var pivot: CGPoint? = nil
}

struct SessionDirectionGuide {
    let origin: CGPoint
    let tip: CGPoint
    let trackedJoint: CGPoint
    var showsArrow = true
    var farthestPosition: CGPoint?
}

/// The tracked body, in normalized image coordinates: an optional shoulder-hip box and midline,
/// and a chain of joints such as shoulder, elbow and wrist.
struct SessionPoseGuide {
    /// Shoulders and hips in drawing order; fewer than three points draws no box.
    var torso: [CGPoint] = []
    var midline: (base: CGPoint, top: CGPoint)?
    var chain: [CGPoint] = []
    /// Further joint chains drawn like `chain`, such as both arms of a whole-body skeleton.
    var limbs: [[CGPoint]] = []
    /// Draws the box and midline in orange instead of yellow.
    var warning = false
    /// How strongly the body is drawn: full guidance, or a quiet outline that only shows tracking.
    enum Emphasis { case guidance, ambient }
    var emphasis: Emphasis = .guidance
}

/// The seconds left in a hold, drawn beside the bubble so it never hides the joint.
struct SessionHoldCountdown {
    let seconds: Int
    let center: CGPoint
    let radius: Double
}

/// Calm camera guidance: a breathing target bubble, a quiet outline-only home bubble, one curved
/// fading arrow and a slow hold ring.
///
/// Shape, not color alone, tells the zones apart (filled and breathing versus outline), and the
/// overlay never uses red. Breathing animates only a halo outside the zone, so the accepted
/// boundary is always the drawn outline. Reduce Motion freezes the halo.
struct TMSessionTargetOverlay: View {
    let imageSize: CGSize?
    let bubbleGuide: SessionBubbleGuide?
    var singleZone = false
    /// False draws only the target bubble, for exercises whose start is not a place to return to.
    var showsStart = true
    var settingUp = false
    var captureJoint: CGPoint? = nil
    var holdProgress = 0.0
    /// Hold ring radius in normalized image height, like a bubble radius; nil keeps the default size.
    var holdRadius: Double? = nil
    var directionGuide: SessionDirectionGuide? = nil
    /// Drawn at full strength whatever the stage, because it guides calibration.
    var movementCue: SessionMovementCue? = nil
    var poseGuide: SessionPoseGuide? = nil
    var holdCountdown: SessionHoldCountdown? = nil
    let mirrored: Bool
    var viewportChanged: ((CGSize) -> Void)? = nil

    /// A finished hold: where the accepted bubble was, in normalized image coordinates.
    private struct Pop {
        let center: CGPoint
        let radius: Double
        let start: Date
    }

    /// The calibration cue's last shape and when it last appeared or went away, kept so it can
    /// fade out after the caller drops it. A reference, so updating it while drawing never
    /// invalidates the view.
    private final class CueMemory {
        var cue: SessionMovementCue?
        var changedAt = Date.distantPast
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: Pop?
    @State private var lastActive: (center: CGPoint, radius: Double)?
    @State private var cueMemory = CueMemory()

    private let breathingPeriod = 4.0
    private let popDuration = 0.6
    private let arrowSweepPeriod = 1.5
    private let cueFadeDuration = 0.25

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            canvas(breath: breath(at: timeline.date), now: timeline.date)
        }
        .onChange(of: bubbleGuide?.dwellProgress) { old, new in
            trackAcceptance(old: old, new: new)
        }
        .onChange(of: movementCue != nil) {
            trackCueVisibility()
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewportChanged?(proxy.size) }
                    .onChange(of: proxy.size) { _, size in
                        viewportChanged?(size)
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 0...1, easing in and out over `breathingPeriod`; a resting value under Reduce Motion.
    private func breath(at date: Date) -> Double {
        guard !reduceMotion else {
            return 0.5
        }

        let phase = date.timeIntervalSinceReferenceDate / breathingPeriod

        return 0.5 - 0.5 * cos(phase * 2 * .pi)
    }

    /// The snapshot resets a hold's progress the moment it is accepted, so a drop from a nearly
    /// full ring is the acceptance cue. Frozen or cleared holds fall from lower values.
    private func trackAcceptance(old: Double?, new: Double?) {
        if let guide = bubbleGuide {
            lastActive = (
                guide.activeZone == .start ? guide.startCenter : guide.targetCenter,
                guide.radius
            )
        }

        guard !reduceMotion,
              let old,
              old >= 0.85,
              (new ?? 0) < old,
              let lastActive else {
            return
        }

        pop = Pop(center: lastActive.center, radius: lastActive.radius, start: Date())
    }

    private func canvas(breath: Double, now: Date) -> some View {
        Canvas { context, size in
            guard let image = imageSize, image.width > 0, image.height > 0 else { return }
            let geometry = CameraDisplayGeometry(aspect: image.width / image.height, viewport: size)
            let scale = geometry.imageRect.height / image.height
            let offset = geometry.imageRect.origin
            func point(_ point: CGPoint) -> CGPoint {
                geometry.point(point, mirrored: mirrored)
            }
            let imageBounds = CGRect(
                origin: offset,
                size: CGSize(width: image.width * scale, height: image.height * scale)
            )

            if let poseGuide {
                drawPose(poseGuide, point: point, context: &context)
            }

            if let directionGuide {
                if directionGuide.showsArrow {
                    drawReachDirection(
                        from: point(directionGuide.origin),
                        to: point(directionGuide.tip),
                        bounds: imageBounds,
                        now: now,
                        context: &context
                    )
                }

                if let farthest = directionGuide.farthestPosition {
                    drawFarthest(point(farthest), bounds: imageBounds, context: &context)
                }

                drawJoint(point(directionGuide.trackedJoint), context: &context)
            }

            if let guide = bubbleGuide {
                let radius = guide.radius * image.height * scale
                let start = point(guide.startCenter)
                let target = point(guide.targetCenter)

                // The saved start is only a reference during reach capture, never a destination.
                // Once a hold has begun, the hold ring is the only active cue.
                if !settingUp, !guide.trackedJointInside, guide.dwellProgress == 0, let tracked = guide.trackedJoint {
                    drawDirection(
                        from: point(tracked),
                        to: guide.activeZone == .start ? start : target,
                        radius: radius,
                        pivot: guide.pivot.map(point),
                        bounds: imageBounds,
                        now: now,
                        context: &context
                    )
                }

                if showsStart || singleZone {
                    drawBubble(.start, center: start, radius: radius, breath: breath, guide: guide, context: &context)
                }

                if !settingUp && !singleZone {
                    drawBubble(.target, center: target, radius: radius, breath: breath, guide: guide, context: &context)
                }

                if !settingUp, let tracked = guide.trackedJoint {
                    drawJoint(point(tracked), context: &context)
                }
            }

            if let pop {
                drawPop(pop, scale: scale, imageHeight: image.height, at: point(pop.center), now: now, context: &context)
            }

            if let holdCountdown {
                drawCountdown(
                    holdCountdown,
                    center: point(holdCountdown.center),
                    radius: holdCountdown.radius * image.height * scale,
                    bounds: imageBounds,
                    context: &context
                )
            }

            let holdRingRadius = holdRadius.map { $0 * image.height * scale } ?? 60

            if let joint = captureJoint {
                let center = point(joint)
                drawJointHold(
                    center: center,
                    progress: holdProgress,
                    radius: holdRingRadius,
                    context: &context
                )
            }

            // Above the hold ring, so the joint indicator never covers it.
            if let cue = movementCue ?? cueMemory.cue {
                cueMemory.cue = cue

                // Start just outside the ring's outer edge (half its 22 pt stroke) when one is drawn.
                let gap = captureJoint == nil ? 26 : holdRingRadius + 11 + 6

                drawCurvedArrow(
                    from: point(cue.tail),
                    to: point(cue.tip),
                    pivot: cue.pivot.map(point),
                    trimStart: gap,
                    trimEnd: 0,
                    minimumVisible: 90,
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

    /// The farthest reach so far: a hollow blue ring around a white point, with a label in the hold
    /// count's badge style below it.
    ///
    /// Hollow and much smaller than a bubble, so it reads as a reference rather than a destination,
    /// and its color and shape keep it apart from the yellow joint disc.
    private func drawFarthest(_ point: CGPoint, bounds: CGRect, context: inout GraphicsContext) {
        let ringRadius = 18.0
        let ring = Path(ellipseIn: CGRect(
            x: point.x - ringRadius,
            y: point.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))
        strokeWithUnderlay(ring, color: TherapyPalette.guidanceBlue, width: 6, context: &context)

        let dot = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: dot.insetBy(dx: -3, dy: -3)), with: .color(TherapyPalette.calmUnderlay))
        context.fill(Path(ellipseIn: dot), with: .color(.white))

        let text = context.resolve(AppTypography.overlayText("parity.farthest", size: 22, weight: .semiBold))
        let measured = text.measure(in: CGSize(width: max(1, bounds.width - 16), height: .infinity))
        let width = min(max(0, bounds.width - 16), measured.width + 28)
        let height = min(max(0, bounds.height - 16), measured.height + 12)

        guard width > 0, height > 0 else {
            return
        }

        // Only the label moves at the image edge; the mark stays on the measured point. Below the
        // mark unless that leaves the picture, then above it, so the label never covers the mark.
        let below = point.y + ringRadius + 12
        let above = point.y - ringRadius - 12 - height
        let top = below + height <= bounds.maxY - 8 ? below : above
        let rect = CGRect(
            x: min(max(point.x - width / 2, bounds.minX + 8), bounds.maxX - width - 8),
            y: min(max(top, bounds.minY + 8), bounds.maxY - height - 8),
            width: width,
            height: height
        )
        let badge = Path(roundedRect: rect, cornerRadius: height / 2)
        context.fill(badge, with: .color(TherapyPalette.calmUnderlay))
        context.stroke(badge, with: .color(TherapyPalette.guidanceBlue), lineWidth: 3)
        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// The body outline under the bubbles: a quiet shoulder-hip box and midline, and the joint
    /// chain in the same dark-underlay style as every other line.
    private func drawPose(
        _ pose: SessionPoseGuide,
        point: (CGPoint) -> CGPoint,
        context: inout GraphicsContext
    ) {
        if pose.emphasis == .ambient {
            drawAmbientPose(pose, point: point, context: &context)
            return
        }

        let torsoColor = pose.warning ? Color.orange : TherapyPalette.guidanceYellow

        if pose.torso.count > 2 {
            var torso = Path()
            torso.move(to: point(pose.torso[0]))
            pose.torso.dropFirst().forEach { torso.addLine(to: point($0)) }
            torso.closeSubpath()
            context.fill(torso, with: .color(torsoColor.opacity(0.10)))
            strokeWithUnderlay(torso, color: torsoColor.opacity(0.75), width: 3, context: &context)
        }

        if let midline = pose.midline {
            var path = Path()
            path.move(to: point(midline.base))
            path.addLine(to: point(midline.top))
            strokeWithUnderlay(
                path,
                color: torsoColor,
                width: 5,
                style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [12, 8]),
                context: &context
            )
        }

        for joints in [pose.chain] + pose.limbs {
            guard let chain = chainPath(joints, point: point) else {
                continue
            }

            strokeWithUnderlay(chain, color: .white, width: 6, context: &context)
            joints.forEach { drawJoint(point($0), context: &context) }
        }
    }

    /// The tracked body while no guidance is shown, such as during narration: thin, half-strength
    /// lines and small dots that only tell the patient they are followed. It carries no guidance,
    /// so the visibility minimums for guidance shapes do not apply.
    private func drawAmbientPose(
        _ pose: SessionPoseGuide,
        point: (CGPoint) -> CGPoint,
        context: inout GraphicsContext
    ) {
        // One layer, so overlapping lines and dots fade together instead of stacking.
        context.drawLayer { layer in
            layer.opacity = 0.5

            if pose.torso.count > 2 {
                var torso = Path()
                torso.move(to: point(pose.torso[0]))
                pose.torso.dropFirst().forEach { torso.addLine(to: point($0)) }
                torso.closeSubpath()
                strokeWithUnderlay(torso, color: .white, width: 3, context: &layer)
            }

            for joints in [pose.chain] + pose.limbs {
                guard let chain = chainPath(joints, point: point) else {
                    continue
                }

                strokeWithUnderlay(chain, color: .white, width: 3, context: &layer)
                joints.forEach { drawAmbientJoint(point($0), context: &layer) }
            }
        }
    }

    /// The joints joined in order; nil for fewer than two joints.
    private func chainPath(_ joints: [CGPoint], point: (CGPoint) -> CGPoint) -> Path? {
        guard joints.count > 1 else {
            return nil
        }

        var chain = Path()
        chain.move(to: point(joints[0]))
        joints.dropFirst().forEach { chain.addLine(to: point($0)) }

        return chain
    }

    /// The count sits just outside the bubble, above it unless that would leave the picture.
    private func drawCountdown(
        _ countdown: SessionHoldCountdown,
        center: CGPoint,
        radius: Double,
        bounds: CGRect,
        context: inout GraphicsContext
    ) {
        let badge = 54.0
        let gap = 14.0
        let above = center.y - radius - gap - badge / 2
        let badgeCenter = CGPoint(
            x: center.x,
            y: above - badge / 2 >= bounds.minY ? above : center.y + radius + gap + badge / 2
        )
        let rect = CGRect(
            x: badgeCenter.x - badge / 2,
            y: badgeCenter.y - badge / 2,
            width: badge,
            height: badge
        )

        context.fill(Path(ellipseIn: rect), with: .color(TherapyPalette.calmUnderlay))
        context.stroke(Path(ellipseIn: rect), with: .color(TherapyPalette.guidanceBlue), lineWidth: 3)
        context.draw(
            context.resolve(
                AppTypography.overlayText(LocalizedStringKey(String(countdown.seconds)), size: 32, weight: .bold)
            ),
            at: badgeCenter
        )
    }

    /// The tracked joint: a large yellow disc the patient can always find.
    private func drawJoint(_ point: CGPoint, context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)
        let disc = Path(ellipseIn: rect)
        context.fill(Path(ellipseIn: rect.insetBy(dx: -7, dy: -7)), with: .color(TherapyPalette.calmUnderlay))
        context.fill(disc, with: .color(TherapyPalette.guidanceYellow))
        context.stroke(disc, with: .color(.white), lineWidth: 5)
    }

    /// A small white joint dot for the ambient body, with no yellow and no ring.
    private func drawAmbientJoint(_ point: CGPoint, context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
        context.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(TherapyPalette.calmUnderlay))
        context.fill(Path(ellipseIn: rect), with: .color(.white))
    }

    private func drawBubble(
        _ zone: SessionBubbleGuide.Zone,
        center: CGPoint,
        radius: Double,
        breath: Double,
        guide: SessionBubbleGuide,
        context: inout GraphicsContext
    ) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let outline = Path(ellipseIn: rect)
        let active = !settingUp && guide.activeZone == zone
        let arrived = active && guide.trackedJointInside

        switch zone {
        case .start:
            // Home: outline only, so it reads differently from the filled target.
            if active {
                strokeWithUnderlay(outline, color: TherapyPalette.guidanceYellow, width: 7, context: &context)
            } else {
                strokeWithUnderlay(
                    outline,
                    color: TherapyPalette.guidanceYellow.opacity(0.7),
                    width: 3.5,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [8, 10]),
                    context: &context
                )
            }
        case .target:
            guard active else {
                strokeWithUnderlay(outline, color: TherapyPalette.guidanceBlue.opacity(0.7), width: 3.5, context: &context)
                break
            }

            // The halo breathes outside the zone; the filled disc and outline do not move.
            let halo = radius * (1.06 + 0.12 * breath)
            let haloRect = CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)
            context.stroke(
                Path(ellipseIn: haloRect),
                with: .color(TherapyPalette.guidanceBlue.opacity(0.4 + 0.3 * (1 - breath))),
                lineWidth: 10
            )
            context.fill(
                outline,
                with: .radialGradient(
                    Gradient(colors: [
                        TherapyPalette.guidanceBlue.opacity(arrived ? 0.65 : 0.5),
                        TherapyPalette.guidanceBlue.opacity(arrived ? 0.9 : 0.75)
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            strokeWithUnderlay(outline, color: TherapyPalette.guidanceBlue, width: 10, context: &context)
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: 7, dy: 7)),
                with: .color(.white.opacity(0.9)),
                lineWidth: 3
            )
        }

        if active, guide.dwellProgress > 0 {
            // Progress follows the perimeter; the acceptance boundary never moves.
            drawRing(center: center, radius: radius, progress: guide.dwellProgress, context: &context)
        }
    }

    /// The hold around the tracked joint: a large ring that is visible from the first frame of the
    /// hold, with a blue fill that grows as the hold completes. It carries no numbers.
    private func drawJointHold(
        center: CGPoint,
        progress: Double,
        radius: Double,
        context: inout GraphicsContext
    ) {
        let clamped = min(1, max(0, progress))
        let track = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        // Dark underlay first, so the ring reads on any camera image.
        context.stroke(track, with: .color(TherapyPalette.calmUnderlay), lineWidth: 22)
        context.stroke(track, with: .color(.white.opacity(0.45)), lineWidth: 14)

        if clamped > 0 {
            let fill = radius * clamped
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - fill, y: center.y - fill, width: fill * 2, height: fill * 2)),
                with: .color(TherapyPalette.guidanceBlue.opacity(0.35))
            )

            var arc = Path()
            arc.addArc(
                center: center, radius: radius,
                startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * clamped),
                clockwise: false
            )
            context.stroke(arc, with: .color(TherapyPalette.calmUnderlay), style: StrokeStyle(lineWidth: 22, lineCap: .round))
            context.stroke(arc, with: .color(TherapyPalette.guidanceBlue), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        }

        drawJoint(center, context: &context)
    }

    /// A bold progress ring over a faint full track. It carries no numbers.
    private func drawRing(center: CGPoint, radius: Double, progress: Double, context: inout GraphicsContext) {
        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return }

        let track = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(track, with: .color(.white.opacity(0.3)), lineWidth: 10)

        var arc = Path()
        arc.addArc(
            center: center, radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * clamped),
            clockwise: false
        )
        strokeWithUnderlay(arc, color: .white, width: 10, context: &context)
    }

    /// A soft expanding, fading ring where a hold was just accepted. Never flashes.
    private func drawPop(
        _ pop: Pop, scale: Double, imageHeight: Double, at center: CGPoint, now: Date, context: inout GraphicsContext
    ) {
        let progress = now.timeIntervalSince(pop.start) / popDuration
        guard progress >= 0, progress < 1 else { return }

        let eased = 1 - pow(1 - progress, 3)
        let radius = pop.radius * imageHeight * scale * (1 + 0.35 * eased)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(TherapyPalette.guidanceBlue.opacity(0.85 * (1 - progress))),
            lineWidth: 8 * (1 - progress) + 1
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
    /// beyond `trimStart`; arrows that must end at a bubble pass zero.
    private func drawCurvedArrow(
        from tail: CGPoint,
        to tip: CGPoint,
        pivot: CGPoint?,
        trimStart: Double,
        trimEnd: Double,
        minimumVisible: Double = 0,
        fade: Double,
        bounds: CGRect,
        now: Date,
        context: inout GraphicsContext
    ) {
        guard fade > 0 else {
            return
        }

        let end = minimumVisible > 0
            ? extendedTip(from: tail, to: tip, pivot: pivot, trim: trimStart, visible: minimumVisible)
            : tip
        let curve = curvePoints(from: tail, to: end, pivot: pivot, bounds: bounds)

        // The end is trimmed by trimming the reversed curve from its start.
        guard let afterTail = trimmed(curve, outside: tail, radius: trimStart),
              let beforeEnd = trimmed(Array(afterTail.reversed()), outside: end, radius: trimEnd) else {
            return
        }

        let points = Array(beforeEnd.reversed())

        guard let point = points.last,
              polylineLength(points) >= 30 else {
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

        context.drawLayer { layer in
            layer.opacity = fade

            layer.stroke(shaft, with: .color(TherapyPalette.calmUnderlay), style: round)
            layer.stroke(head, with: .color(TherapyPalette.calmUnderlay), style: round)

            var line = round
            line.lineWidth = Self.arrowShaftWidth
            layer.stroke(shaft, with: .color(.white.opacity(reduceMotion ? 1 : 0.55)), style: line)

            if !reduceMotion {
                // A stretch a quarter of the shaft long enters at the tail and leaves at the head.
                let front = (now.timeIntervalSinceReferenceDate / arrowSweepPeriod)
                    .truncatingRemainder(dividingBy: 1) * 1.25
                let highlight = shaft.trimmedPath(from: max(0, front - 0.25), to: min(1, front))
                layer.stroke(highlight, with: .color(.white), style: line)
            }

            // The chevron stays full strength, so the direction reads even between sweeps.
            layer.stroke(head, with: .color(.white), style: line)
        }
    }

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
