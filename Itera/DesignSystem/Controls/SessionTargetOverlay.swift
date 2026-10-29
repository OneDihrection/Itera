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

struct SessionTargetOverlay: View {
    let imageSize: CGSize?
    let bubbleGuide: SessionBubbleGuide?
    var singleZone = false
    var settingUp = false
    var captureJoint: CGPoint? = nil
    var holdProgress = 0.0
    var directionGuide: SessionDirectionGuide? = nil
    let mirrored: Bool
    var viewportChanged: ((CGSize) -> Void)? = nil

    @ScaledMetric(relativeTo: .title) private var labelSize = 32.0

    var body: some View {
        Canvas { context, size in
            guard let image = imageSize, image.width > 0, image.height > 0 else { return }
            let scale = min(size.width / image.width, size.height / image.height)
            let offset = CGPoint(x: (size.width - image.width * scale) / 2, y: (size.height - image.height * scale) / 2)
            func point(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: offset.x + (mirrored ? 1 - point.x : point.x) * image.width * scale,
                    y: offset.y + (1 - point.y) * image.height * scale
                )
            }
            if let directionGuide {
                let bounds = CGRect(origin: offset, size: CGSize(width: image.width * scale, height: image.height * scale))
                if directionGuide.showsArrow {
                    drawReachDirection(
                        from: point(directionGuide.origin), to: point(directionGuide.tip),
                        bounds: bounds, context: &context
                    )
                }
                if let farthest = directionGuide.farthestPosition {
                    drawFarthest(point(farthest), bounds: bounds, context: &context)
                }
                drawJoint(point(directionGuide.trackedJoint), color: .yellow, context: &context)
            }
            if let guide = bubbleGuide {
                let radius = guide.radius * image.height * scale
                let start = point(guide.startCenter)
                let target = point(guide.targetCenter)
                let imageBounds = CGRect(origin: offset, size: CGSize(width: image.width * scale, height: image.height * scale))

                // The saved start is only a reference during reach capture, never a destination.
                if !settingUp, !guide.trackedJointInside, let tracked = guide.trackedJoint {
                    drawDirection(
                        from: point(tracked),
                        to: guide.activeZone == .start ? start : target,
                        radius: radius,
                        context: &context
                    )
                }

                drawBubble(.start, center: start, radius: radius, guide: guide, context: &context)
                if !settingUp && !singleZone {
                    drawBubble(.target, center: target, radius: radius, guide: guide, context: &context)
                }
                if !settingUp, let tracked = guide.trackedJoint {
                    drawJoint(point(tracked), color: directionGuide != nil ? .yellow : (guide.trackedJointInside ? .green : .yellow), context: &context)
                }

                drawLabel(
                    .start, center: start, radius: radius, above: settingUp || start.y <= target.y,
                    bounds: imageBounds, guide: guide, context: &context
                )
                if !settingUp && !singleZone {
                    drawLabel(
                        .target, center: target, radius: radius, above: target.y < start.y,
                        bounds: imageBounds, guide: guide, context: &context
                    )
                }
            }
            if let joint = captureJoint {
                let center = point(joint)
                drawJoint(center, color: .yellow, context: &context)
                let ring = CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60)
                context.stroke(Path(ellipseIn: ring), with: .color(.black), lineWidth: 10)
                context.stroke(Path(ellipseIn: ring), with: .color(.white), lineWidth: 3)
                var arc = Path()
                arc.addArc(center: center, radius: 30, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * holdProgress), clockwise: false)
                context.stroke(arc, with: .color(.yellow), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }
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

    /// Keep the direction cue visible at the image edge without changing measured coordinates.
    private func drawReachDirection(from origin: CGPoint, to tip: CGPoint, bounds: CGRect, context: inout GraphicsContext) {
        let distance = hypot(tip.x - origin.x, tip.y - origin.y)
        guard distance > 0, bounds.width > 64, bounds.height > 64 else { return }
        let dx = (tip.x - origin.x) / distance
        let dy = (tip.y - origin.y) / distance
        let length = min(max(distance, 90), min(bounds.width, bounds.height) * 0.35)
        let inset = bounds.insetBy(dx: 24, dy: 24)
        let tail = CGPoint(
            x: min(max(origin.x, inset.minX + max(0, -dx * length)), inset.maxX - max(0, dx * length)),
            y: min(max(origin.y, inset.minY + max(0, -dy * length)), inset.maxY - max(0, dy * length))
        )
        let head = CGPoint(x: tail.x + dx * length, y: tail.y + dy * length)
        let headLength = min(32, length * 0.3)
        var arrow = Path()
        arrow.move(to: tail)
        arrow.addLine(to: head)
        arrow.move(to: CGPoint(x: head.x - dx * headLength - dy * headLength * 0.7, y: head.y - dy * headLength + dx * headLength * 0.7))
        arrow.addLine(to: head)
        arrow.addLine(to: CGPoint(x: head.x - dx * headLength + dy * headLength * 0.7, y: head.y - dy * headLength - dx * headLength * 0.7))
        context.stroke(arrow, with: .color(.black), style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
        context.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
    }

    private func drawFarthest(_ point: CGPoint, bounds: CGRect, context: inout GraphicsContext) {
        var diamond = Path()
        diamond.move(to: CGPoint(x: point.x, y: point.y - 18))
        diamond.addLine(to: CGPoint(x: point.x + 18, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + 18))
        diamond.addLine(to: CGPoint(x: point.x - 18, y: point.y))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(.pink))
        context.stroke(diamond, with: .color(.black), lineWidth: 4)

        let text = context.resolve(AppTypography.overlayText("parity.farthest", size: 22, weight: .bold))
        let measured = text.measure(in: CGSize(width: max(1, bounds.width - 16), height: .infinity))
        let width = min(max(0, bounds.width - 16), measured.width + 16)
        let height = min(max(0, bounds.height - 16), measured.height + 8)
        guard width > 0, height > 0 else { return }
        // Only the label moves at the image edge; the measured diamond stays put.
        let rect = CGRect(
            x: min(max(point.x - width / 2, bounds.minX + 8), bounds.maxX - width - 8),
            y: min(max(point.y + 26, bounds.minY + 8), bounds.maxY - height - 8),
            width: width, height: height
        )
        context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(.black.opacity(0.9)))
        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func drawJoint(_ point: CGPoint, color: Color, context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.stroke(Path(ellipseIn: rect), with: .color(.black), lineWidth: 3)
    }

    private func drawBubble(_ zone: SessionBubbleGuide.Zone, center: CGPoint, radius: Double, guide: SessionBubbleGuide, context: inout GraphicsContext) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let active = !settingUp && guide.activeZone == zone
        let arrived = active && guide.trackedJointInside
        let color: Color = arrived ? .green : (zone == .start ? .cyan : .orange)
        context.stroke(Path(ellipseIn: rect), with: .color(.black), lineWidth: active ? 11 : 6)
        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(active ? 0.3 : 0.04)))
        context.stroke(Path(ellipseIn: rect), with: .color(active ? color : .white), lineWidth: active ? 6 : 2)
        if arrived, guide.dwellProgress > 0 {
            // Progress follows the perimeter; the acceptance boundary never moves.
            var arc = Path()
            arc.addArc(
                center: center, radius: radius,
                startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * guide.dwellProgress),
                clockwise: false
            )
            context.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
    }

    private func drawDirection(from joint: CGPoint, to center: CGPoint, radius: Double, context: inout GraphicsContext) {
        let distance = hypot(center.x - joint.x, center.y - joint.y)
        let available = distance - radius - 14
        guard available > 4 else { return }

        let dx = (center.x - joint.x) / distance
        let dy = (center.y - joint.y) / distance
        let tip = CGPoint(x: center.x - dx * radius, y: center.y - dy * radius)
        let head = min(18, available * 0.5)
        var arrow = Path()
        arrow.move(to: CGPoint(x: joint.x + dx * 14, y: joint.y + dy * 14))
        arrow.addLine(to: tip)
        arrow.move(to: CGPoint(x: tip.x - dx * head - dy * head * 0.6, y: tip.y - dy * head + dx * head * 0.6))
        arrow.addLine(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x - dx * head + dy * head * 0.6, y: tip.y - dy * head - dx * head * 0.6))
        context.stroke(arrow, with: .color(.black), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        context.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    private func drawLabel(
        _ zone: SessionBubbleGuide.Zone, center: CGPoint, radius: Double, above: Bool,
        bounds: CGRect, guide: SessionBubbleGuide, context: inout GraphicsContext
    ) {
        let active = !settingUp && guide.activeZone == zone
        let color: Color = active && guide.trackedJointInside ? .green : (zone == .start ? .cyan : .orange)
        let text = context.resolve(
            AppTypography.overlayText(
                zone == .start ? "session.startLabel" : "session.targetLabel",
                size: labelSize,
                weight: active ? .bold : .medium
            )
        )
        let measured = text.measure(in: CGSize(width: max(1, bounds.width - 40), height: .infinity))
        let width = min(bounds.width - 16, measured.width + 24)
        let height = min(bounds.height - 16, measured.height + 12)
        guard width > 0, height > 0 else { return }

        // Keep labels inside the fitted camera image without shifting measured zones.
        let preferredY = above ? center.y - radius - 12 - height : center.y + radius + 12
        let rect = CGRect(
            x: min(max(center.x - width / 2, bounds.minX + 8), bounds.maxX - width - 8),
            y: min(max(preferredY, bounds.minY + 8), bounds.maxY - height - 8),
            width: width, height: height
        )
        let background = Path(roundedRect: rect, cornerRadius: 12)
        context.fill(background, with: .color(.black.opacity(0.9)))
        context.stroke(background, with: .color(active ? color : .white.opacity(0.6)), lineWidth: active ? 3 : 1)
        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
    }
}

