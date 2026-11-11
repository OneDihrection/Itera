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
}

/// The seconds left in a hold, drawn beside the bubble so it never hides the joint.
struct SessionHoldCountdown {
    let seconds: Int
    let center: CGPoint
    let radius: Double
}

/// Calm camera guidance: a breathing target bubble, a quiet outline-only home bubble, one thin
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: Pop?
    @State private var lastActive: (center: CGPoint, radius: Double)?

    private let breathingPeriod = 4.0
    private let popDuration = 0.6
    private let chevronPeriod = 1.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            canvas(breath: breath(at: timeline.date), now: timeline.date)
        }
        .onChange(of: bubbleGuide?.dwellProgress) { old, new in
            trackAcceptance(old: old, new: new)
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

            if let joint = captureJoint {
                let center = point(joint)
                drawJointHold(
                    center: center,
                    progress: holdProgress,
                    radius: holdRadius.map { $0 * image.height * scale } ?? 60,
                    context: &context
                )
            }
        }
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

        drawChevronTrail(from: tail, to: head, fade: 1, now: now, context: &context)
    }

    private func drawFarthest(_ point: CGPoint, bounds: CGRect, context: inout GraphicsContext) {
        var diamond = Path()
        diamond.move(to: CGPoint(x: point.x, y: point.y - 22))
        diamond.addLine(to: CGPoint(x: point.x + 22, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + 22))
        diamond.addLine(to: CGPoint(x: point.x - 22, y: point.y))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(TherapyPalette.guidanceBlue.opacity(0.7)))
        strokeWithUnderlay(diamond, color: .white, width: 4, context: &context)

        let text = context.resolve(AppTypography.overlayText("parity.farthest", size: 30, weight: .bold))
        let measured = text.measure(in: CGSize(width: max(1, bounds.width - 16), height: .infinity))
        let width = min(max(0, bounds.width - 16), measured.width + 20)
        let height = min(max(0, bounds.height - 16), measured.height + 10)
        guard width > 0, height > 0 else { return }
        // Only the label moves at the image edge; the measured diamond stays put.
        let rect = CGRect(
            x: min(max(point.x - width / 2, bounds.minX + 8), bounds.maxX - width - 8),
            y: min(max(point.y + 32, bounds.minY + 8), bounds.maxY - height - 8),
            width: width, height: height
        )
        context.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(.black.opacity(0.75)))
        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// The body outline under the bubbles: a quiet shoulder-hip box and midline, and the joint
    /// chain in the same dark-underlay style as every other line.
    private func drawPose(
        _ pose: SessionPoseGuide,
        point: (CGPoint) -> CGPoint,
        context: inout GraphicsContext
    ) {
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
            drawChain(joints, point: point, context: &context)
        }
    }

    private func drawChain(
        _ joints: [CGPoint],
        point: (CGPoint) -> CGPoint,
        context: inout GraphicsContext
    ) {
        guard joints.count > 1 else {
            return
        }

        var chain = Path()
        chain.move(to: point(joints[0]))
        joints.dropFirst().forEach { chain.addLine(to: point($0)) }
        strokeWithUnderlay(chain, color: .white, width: 6, context: &context)
        joints.forEach { drawJoint(point($0), context: &context) }
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
        from joint: CGPoint, to center: CGPoint, radius: Double, now: Date, context: inout GraphicsContext
    ) {
        let distance = hypot(center.x - joint.x, center.y - joint.y)
        let available = distance - radius - 20
        guard available > 4 else { return }

        let dx = (center.x - joint.x) / distance
        let dy = (center.y - joint.y) / distance
        let tail = CGPoint(x: joint.x + dx * 26, y: joint.y + dy * 26)
        let tip = CGPoint(x: center.x - dx * (radius + 14), y: center.y - dy * (radius + 14))

        // The trail fades over the last stretch so it leaves quietly as the joint arrives.
        let fade = min(1, max(0, (available - 4) / 60))

        drawChevronTrail(from: tail, to: tip, fade: fade, now: now, context: &context)
    }

    /// A few small chevrons along the path, brightening in sequence toward the target.
    ///
    /// There is no shaft, so the cue stays quiet over long distances. The sequence is static
    /// under Reduce Motion, brighter toward the target.
    private func drawChevronTrail(
        from tail: CGPoint, to tip: CGPoint, fade: Double, now: Date, context: inout GraphicsContext
    ) {
        let length = hypot(tip.x - tail.x, tip.y - tail.y)
        guard length > 24, fade > 0 else { return }

        let dx = (tip.x - tail.x) / length
        let dy = (tip.y - tail.y) / length
        let count = min(4, max(1, Int(length / 80)))
        let front = reduceMotion ? 0 : (now.timeIntervalSinceReferenceDate / chevronPeriod)
            .truncatingRemainder(dividingBy: 1) * Double(count + 1) - 0.5

        for index in 0..<count {
            let along = (Double(index) + 0.5) / Double(count) * length
            let center = CGPoint(x: tail.x + dx * along, y: tail.y + dy * along)
            let brightness = reduceMotion
                ? Double(index + 1) / Double(count)
                : max(0, 1 - abs(front - Double(index)))

            var chevron = Path()
            chevron.move(to: CGPoint(x: center.x - dx * 9 - dy * 15, y: center.y - dy * 9 + dx * 15))
            chevron.addLine(to: CGPoint(x: center.x + dx * 9, y: center.y + dy * 9))
            chevron.addLine(to: CGPoint(x: center.x - dx * 9 + dy * 15, y: center.y - dy * 9 - dx * 15))

            context.drawLayer { layer in
                layer.opacity = (0.4 + 0.6 * brightness) * fade
                strokeWithUnderlay(chevron, color: .white, width: 7, context: &layer)
            }
        }
    }
}
