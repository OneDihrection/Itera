//
//  SkeletonReplay.swift
//  Tuntun
//
//  Created by dimaswisodewo on 12/11/2026.
//

import SwiftUI

/// One recorded pose. Points are normalized image coordinates (origin bottom-left, unmirrored);
/// nil marks a joint that was not tracked in this pose.
struct TMSkeletonPose {
    let time: Double
    let points: [CGPoint?]
}

/// A line between two indices of `TMSkeletonPose.points`.
struct TMSkeletonBone {
    let from: Int
    let to: Int
}

/// Replays recorded poses as a stick figure with play/pause and a scrubber.
///
/// The figure is framed to the union of all poses, so it stays large however far the person
/// stood from the camera. It loops while playing; under Reduce Motion it starts paused at the
/// midpoint. It knows nothing about exercises: the caller supplies poses, bones and which
/// joints to emphasize.
struct TMSkeletonReplay: View {
    let poses: [TMSkeletonPose]
    let bones: [TMSkeletonBone]
    /// Image width divided by height, so normalized points are drawn without distortion.
    let aspectRatio: Double
    /// Mirrors the figure to match the front-camera preview the patient saw.
    var mirrored = true
    /// Bones whose two ends are both emphasized are drawn as the moving limb.
    var emphasizedJoints: Set<Int> = []
    /// The moving limb, its joints and the playback controls.
    var emphasisColor: Color = TherapyPalette.brand
    var height: CGFloat = 240
    /// Draws the pose as a filled silhouette instead of a stick figure.
    var figure: TMFigureShape? = nil
    let accessibilityLabel: Text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = false
    @State private var pausedTime: Double
    @State private var anchor = Date()

    private let duration: Double
    private let bounds: CGRect

    init(
        poses: [TMSkeletonPose],
        bones: [TMSkeletonBone],
        aspectRatio: Double,
        mirrored: Bool = true,
        emphasizedJoints: Set<Int> = [],
        emphasisColor: Color = TherapyPalette.brand,
        height: CGFloat = 240,
        figure: TMFigureShape? = nil,
        accessibilityLabel: Text
    ) {
        self.poses = poses
        self.bones = bones
        self.aspectRatio = aspectRatio
        self.mirrored = mirrored
        self.emphasizedJoints = emphasizedJoints
        self.emphasisColor = emphasisColor
        self.height = height
        self.figure = figure
        self.accessibilityLabel = accessibilityLabel

        let duration = max(poses.last?.time ?? 0, 0.01)
        self.duration = duration
        _pausedTime = State(initialValue: duration / 2)
        bounds = Self.framing(
            poses,
            aspectRatio: aspectRatio,
            mirrored: mirrored,
            padding: figure == nil ? Self.stickPadding : TMFigureRenderer.padding
        )
    }

    var body: some View {
        TimelineView(.animation(paused: !playing)) { context in
            let time = currentTime(at: context.date)

            VStack(spacing: 8) {
                figure(at: time)
                controls(at: time)
            }
        }
        .onAppear {
            guard !reduceMotion, poses.count > 1 else {
                return
            }

            pausedTime = 0
            anchor = .now
            playing = true
        }
    }

    // MARK: - Sections

    private func figure(at time: Double) -> some View {
        Canvas { context, size in
            if let figure {
                drawFigure(pose(at: time), shape: figure, in: &context, size: size)
            } else {
                draw(pose(at: time), in: &context, size: size)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(
            figure == nil ? TherapyPalette.progressPanel : TherapyPalette.historyCard,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private func controls(at time: Double) -> some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .typography(.title3, weight: .semiBold)
                    .foregroundStyle(TherapyPalette.onBrand)
                    .frame(width: 52, height: 52)
                    .background(emphasisColor, in: Circle())
            }
            .accessibilityLabel(Text(playing ? "replay.pause" : "replay.play"))

            Slider(
                value: Binding(
                    get: { time },
                    set: { scrub(to: $0) }
                ),
                in: 0...duration
            )
            .tint(emphasisColor)
            .accessibilityLabel(Text("replay.position"))
        }
    }

    // MARK: - Playback

    private func currentTime(at date: Date) -> Double {
        guard playing else {
            return pausedTime
        }

        return (pausedTime + date.timeIntervalSince(anchor))
            .truncatingRemainder(dividingBy: duration)
    }

    private func togglePlayback() {
        if playing {
            pausedTime = currentTime(at: .now)
            playing = false
        } else {
            anchor = .now
            playing = true
        }
    }

    private func scrub(to time: Double) {
        playing = false
        pausedTime = min(max(0, time), duration)
    }

    /// The latest pose at or before `time`, found by binary search over the time-ordered poses.
    private func pose(at time: Double) -> TMSkeletonPose? {
        guard !poses.isEmpty else {
            return nil
        }

        var low = 0
        var high = poses.count - 1

        while low < high {
            let middle = (low + high + 1) / 2

            if poses[middle].time <= time {
                low = middle
            } else {
                high = middle - 1
            }
        }

        return poses[low]
    }

    // MARK: - Drawing

    private func drawFigure(
        _ pose: TMSkeletonPose?,
        shape: TMFigureShape,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard let pose else {
            return
        }

        let renderer = TMFigureRenderer(
            shape: shape,
            bounds: bounds,
            size: size,
            aspectRatio: aspectRatio,
            mirrored: mirrored,
            emphasizedJoints: emphasizedJoints
        )

        renderer.drawBody(pose, emphasisColor: emphasisColor, in: &context)
    }

    private func draw(_ pose: TMSkeletonPose?, in context: inout GraphicsContext, size: CGSize) {
        guard let pose, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let offset = CGPoint(
            x: (size.width - bounds.width * scale) / 2,
            y: (size.height - bounds.height * scale) / 2
        )
        let points = pose.points.map { point in
            point.map { normalized -> CGPoint in
                let placed = Self.place(normalized, aspectRatio: aspectRatio, mirrored: mirrored)
                return CGPoint(
                    x: offset.x + (placed.x - bounds.minX) * scale,
                    y: offset.y + (placed.y - bounds.minY) * scale
                )
            }
        }

        for bone in bones {
            guard points.indices.contains(bone.from),
                  points.indices.contains(bone.to),
                  let start = points[bone.from],
                  let end = points[bone.to]
            else {
                continue
            }

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            if emphasizedJoints.contains(bone.from), emphasizedJoints.contains(bone.to) {
                // A white underlay keeps the limb crisp where it crosses the rest of the body.
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                context.stroke(path, with: .color(emphasisColor), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            } else {
                context.stroke(path, with: .color(TherapyPalette.planTrack), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }

        for (index, point) in points.enumerated() {
            guard let point else {
                continue
            }

            let emphasized = emphasizedJoints.contains(index)
            let radius: CGFloat = emphasized ? 8 : 5
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))

            if emphasized {
                context.fill(dot, with: .color(emphasisColor))
                context.stroke(dot, with: .color(.white), lineWidth: 3)
            } else {
                context.fill(dot, with: .color(TherapyPalette.planTrack))
            }
        }
    }

    /// Converts a normalized point into an aspect-correct, y-down space, mirrored when requested.
    static func place(_ point: CGPoint, aspectRatio: Double, mirrored: Bool) -> CGPoint {
        let x = point.x * aspectRatio
        return CGPoint(x: mirrored ? aspectRatio - x : x, y: 1 - point.y)
    }

    /// Stick figures need little room around their joints.
    static let stickPadding = 0.12

    /// The padded union of every placed point, so the figure fills the frame for the whole replay.
    static func framing(
        _ poses: [TMSkeletonPose],
        aspectRatio: Double,
        mirrored: Bool,
        padding paddingFraction: Double = stickPadding
    ) -> CGRect {
        var union = CGRect.null

        for pose in poses {
            for point in pose.points.compactMap({ $0 }) {
                let placed = place(point, aspectRatio: aspectRatio, mirrored: mirrored)
                union = union.union(CGRect(origin: placed, size: .zero))
            }
        }

        guard !union.isNull else {
            return .zero
        }

        let padding = max(union.width, union.height, 0.05) * paddingFraction
        return union.insetBy(dx: -padding, dy: -padding)
    }
}

// MARK: - Figure

/// How to draw a pose as a calm figure: a faint silhouette (round-capped limbs, filled torso or
/// palm, round head) under a thin skeleton with a dot at every joint. Indices refer to
/// `TMSkeletonPose.points`; it knows no anatomy beyond them.
struct TMFigureShape {
    struct Head {
        let center: Int
        /// The head's diameter follows this bone's length (for example shoulder to shoulder).
        let sizeFrom: TMSkeletonBone
        var scale: CGFloat = 0.62
    }

    /// Drawn as the silhouette's capsules.
    let limbs: [TMSkeletonBone]
    /// The thin skeleton drawn over the silhouette.
    let bones: [TMSkeletonBone]
    /// Joints that get a dot; nil marks every joint `bones` uses.
    var joints: Set<Int>? = nil
    /// Polygons filled with rounded corners; one missing point skips the polygon.
    var fills: [[Int]] = []
    var head: Head? = nil
    /// Limb thickness follows this bone's length, times `widthScale`.
    let widthFrom: TMSkeletonBone
    var widthScale: CGFloat = 0.30

    /// The joints dotted on the skeleton.
    var dottedJoints: Set<Int> {
        joints ?? Set(bones.flatMap { [$0.from, $0.to] })
    }
}

/// Draws poses in `TMFigureShape`'s calm style, in one frame shared by every pose drawn: a faint
/// blue-grey silhouette, a thin slate skeleton over it and a small ringed dot at every joint.
/// Bones whose two ends are emphasized, and their joints, are drawn in the emphasis colour over
/// a soft halo of the same colour. A ghost draws only an earlier pose's emphasized limb, dashed.
///
/// Each translucent layer is drawn opaque and faded once through the outer context, so
/// overlapping strokes never darken where they meet.
struct TMFigureRenderer {
    /// Silhouette limbs need more room than stick figures.
    static let padding = 0.18
    static let silhouetteColor = TherapyPalette.badgeRibbonLight
    static let silhouetteOpacity = 0.28
    static let haloOpacity = 0.30
    static let lineWidth: CGFloat = 2.5
    static let emphasisLineWidth: CGFloat = 4
    static let jointRadius: CGFloat = 4.5
    static let emphasisJointRadius: CGFloat = 6

    let shape: TMFigureShape
    let bounds: CGRect
    let size: CGSize
    let aspectRatio: Double
    let mirrored: Bool
    let emphasizedJoints: Set<Int>

    func drawBody(_ pose: TMSkeletonPose, emphasisColor: Color, in context: inout GraphicsContext) {
        let points = placed(pose)

        guard let width = limbWidth(points) else {
            return
        }

        drawSilhouette(points, width: width, in: &context)

        fadedLayer(Self.haloOpacity, in: &context) { layer in
            for bone in shape.limbs where isEmphasized(bone) {
                stroke(bone, points: points, width: width, shading: .color(emphasisColor), in: &layer)
            }
        }

        fadedLayer(0.85, in: &context) { layer in
            for bone in shape.bones where !isMovingBone(bone) {
                stroke(bone, points: points, width: Self.lineWidth, shading: .color(TherapyPalette.figureLine), in: &layer)
            }
        }

        for bone in shape.bones where isMovingBone(bone) {
            stroke(bone, points: points, width: Self.emphasisLineWidth, shading: .color(emphasisColor), in: &context)
        }

        for joint in shape.dottedJoints.sorted() {
            guard let center = point(joint, in: points) else {
                continue
            }

            if movingJoints.contains(joint) {
                drawDot(at: center, radius: Self.emphasisJointRadius, fill: emphasisColor, ring: TherapyPalette.surface, in: &context)
            } else {
                drawDot(at: center, radius: Self.jointRadius, fill: TherapyPalette.surface, ring: TherapyPalette.figureLine, in: &context)
            }
        }
    }

    /// An earlier pose's moving limb: a pale capsule under thin dashed bones and small joint
    /// dots, so its joints stay readable behind the current figure. The colour should be opaque.
    func drawGhost(_ pose: TMSkeletonPose, color: Color, opacity: Double, in context: inout GraphicsContext) {
        let points = placed(pose)

        guard let width = limbWidth(points) else {
            return
        }

        fadedLayer(opacity * 0.25, in: &context) { layer in
            for bone in shape.limbs where isEmphasized(bone) {
                stroke(bone, points: points, width: width, shading: .color(color), in: &layer)
            }
        }

        fadedLayer(opacity * 0.7, in: &context) { layer in
            for bone in shape.bones where isMovingBone(bone) {
                stroke(bone, points: points, width: Self.lineWidth, shading: .color(color), dash: [6, 4], in: &layer)
            }

            for joint in movingJoints.sorted() {
                if let center = point(joint, in: points) {
                    drawDot(at: center, radius: Self.jointRadius, fill: color, ring: TherapyPalette.surface, in: &layer)
                }
            }
        }
    }

    // MARK: Layers

    private func drawSilhouette(_ points: [CGPoint?], width: CGFloat, in context: inout GraphicsContext) {
        let body = GraphicsContext.Shading.color(Self.silhouetteColor)

        fadedLayer(Self.silhouetteOpacity, in: &context) { layer in
            for polygon in shape.fills {
                if let path = fillPath(polygon, points: points) {
                    layer.fill(path, with: body)
                    layer.stroke(path, with: body, style: StrokeStyle(lineWidth: width, lineJoin: .round))
                }
            }

            for bone in shape.limbs {
                stroke(bone, points: points, width: width, shading: body, in: &layer)
            }

            drawHead(points, in: &layer)
        }
    }

    /// Draws `content` opaque into a layer that is faded once as a whole.
    private func fadedLayer(
        _ opacity: Double,
        in context: inout GraphicsContext,
        content: (inout GraphicsContext) -> Void
    ) {
        var faded = context
        faded.opacity = opacity

        faded.drawLayer { layer in
            content(&layer)
        }
    }

    private func drawDot(
        at center: CGPoint,
        radius: CGFloat,
        fill: Color,
        ring: Color,
        in context: inout GraphicsContext
    ) {
        let dot = Path(
            ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )

        context.fill(dot, with: .color(fill))
        context.stroke(dot, with: .color(ring), lineWidth: 2)
    }

    // MARK: Geometry

    private func placed(_ pose: TMSkeletonPose) -> [CGPoint?] {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let offset = CGPoint(
            x: (size.width - bounds.width * scale) / 2,
            y: (size.height - bounds.height * scale) / 2
        )

        return pose.points.map { point in
            point.map { normalized -> CGPoint in
                let placed = TMSkeletonReplay.place(normalized, aspectRatio: aspectRatio, mirrored: mirrored)
                return CGPoint(
                    x: offset.x + (placed.x - bounds.minX) * scale,
                    y: offset.y + (placed.y - bounds.minY) * scale
                )
            }
        }
    }

    private func limbWidth(_ points: [CGPoint?]) -> CGFloat? {
        guard let length = length(of: shape.widthFrom, in: points) else {
            return nil
        }

        return max(length * shape.widthScale, 6)
    }

    private func length(of bone: TMSkeletonBone, in points: [CGPoint?]) -> CGFloat? {
        guard let start = point(bone.from, in: points),
              let end = point(bone.to, in: points)
        else {
            return nil
        }

        return hypot(end.x - start.x, end.y - start.y)
    }

    private func point(_ index: Int, in points: [CGPoint?]) -> CGPoint? {
        points.indices.contains(index) ? points[index] : nil
    }

    private func isEmphasized(_ bone: TMSkeletonBone) -> Bool {
        emphasizedJoints.contains(bone.from) && emphasizedJoints.contains(bone.to)
    }

    /// A skeleton bone of the moving limb: emphasized at both ends and drawn as a limb, so a
    /// reference joint (the hip an arm angle is measured against) never colours the torso side.
    private func isMovingBone(_ bone: TMSkeletonBone) -> Bool {
        isEmphasized(bone)
            && shape.limbs.contains { limb in
                (limb.from == bone.from && limb.to == bone.to)
                    || (limb.from == bone.to && limb.to == bone.from)
            }
    }

    /// Joints of the moving limb's bones, dotted in the emphasis colour.
    private var movingJoints: Set<Int> {
        Set(shape.bones.filter(isMovingBone).flatMap { [$0.from, $0.to] })
    }

    // MARK: Drawing

    private func stroke(
        _ bone: TMSkeletonBone,
        points: [CGPoint?],
        width: CGFloat,
        shading: GraphicsContext.Shading,
        dash: [CGFloat] = [],
        in context: inout GraphicsContext
    ) {
        guard let start = point(bone.from, in: points),
              let end = point(bone.to, in: points)
        else {
            return
        }

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
    }

    /// The polygon, its corners rounded by the stroke drawn over it at limb width.
    private func fillPath(_ polygon: [Int], points: [CGPoint?]) -> Path? {
        let corners = polygon.compactMap { point($0, in: points) }

        guard corners.count == polygon.count, corners.count >= 3 else {
            return nil
        }

        var path = Path()
        path.addLines(corners)
        path.closeSubpath()
        return path
    }

    private func drawHead(_ points: [CGPoint?], in context: inout GraphicsContext) {
        guard let head = shape.head,
              let center = point(head.center, in: points),
              let reference = length(of: head.sizeFrom, in: points)
        else {
            return
        }

        let diameter = max(reference * head.scale, 12)
        let circle = Path(
            ellipseIn: CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
        )

        context.fill(circle, with: .color(Self.silhouetteColor))
    }
}

// MARK: - Comparison

/// Two still poses as silhouettes: an earlier pose's moving limb as a pale ghost behind the
/// current figure, whose moving limb is emphasized, so a patient sees how far the movement now
/// reaches.
///
/// Both poses are framed together. With `alignmentJoint` the earlier pose is shifted so that
/// joint (for example the neck) lands on the current pose's, since the person may have sat
/// elsewhere in the picture. It knows nothing about exercises.
struct TMPoseComparison: View {
    let baseline: TMSkeletonPose?
    let current: TMSkeletonPose
    let figure: TMFigureShape
    /// Image width divided by height, so normalized points are drawn without distortion.
    let aspectRatio: Double
    /// Mirrors the figure to match the front-camera preview the patient saw.
    var mirrored = true
    var alignmentJoint: Int? = nil
    /// Limbs whose two ends are both emphasized are drawn as the moving limb.
    var emphasizedJoints: Set<Int> = []
    var baselineColor: Color = TherapyPalette.guidanceBlue
    var baselineOpacity = 1.0
    var currentColor: Color = TherapyPalette.brand
    var height: CGFloat = 280
    let accessibilityLabel: Text

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(
            TherapyPalette.historyCard,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var alignedBaseline: TMSkeletonPose? {
        guard let baseline else {
            return nil
        }

        guard let alignmentJoint,
              baseline.points.indices.contains(alignmentJoint),
              current.points.indices.contains(alignmentJoint),
              let from = baseline.points[alignmentJoint],
              let to = current.points[alignmentJoint]
        else {
            return baseline
        }

        let dx = to.x - from.x
        let dy = to.y - from.y

        return TMSkeletonPose(
            time: baseline.time,
            points: baseline.points.map { point in
                point.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
        )
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let earlier = alignedBaseline
        let poses = [current] + (earlier.map { [$0] } ?? [])
        let bounds = TMSkeletonReplay.framing(
            poses,
            aspectRatio: aspectRatio,
            mirrored: mirrored,
            padding: TMFigureRenderer.padding
        )

        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let renderer = TMFigureRenderer(
            shape: figure,
            bounds: bounds,
            size: size,
            aspectRatio: aspectRatio,
            mirrored: mirrored,
            emphasizedJoints: emphasizedJoints
        )

        if let earlier {
            renderer.drawGhost(earlier, color: baselineColor, opacity: baselineOpacity, in: &context)
        }

        renderer.drawBody(current, emphasisColor: currentColor, in: &context)
    }
}

#if DEBUG
#Preview("Pose comparison") {
    // nose, neck, left shoulder, right shoulder, left elbow, left wrist, left hip, right hip,
    // right elbow, right wrist
    let figure = TMFigureShape(
        limbs: [
            TMSkeletonBone(from: 0, to: 1),
            TMSkeletonBone(from: 2, to: 4), TMSkeletonBone(from: 4, to: 5),
            TMSkeletonBone(from: 3, to: 8), TMSkeletonBone(from: 8, to: 9),
        ],
        bones: [
            TMSkeletonBone(from: 0, to: 1), TMSkeletonBone(from: 1, to: 2), TMSkeletonBone(from: 1, to: 3),
            TMSkeletonBone(from: 2, to: 4), TMSkeletonBone(from: 4, to: 5),
            TMSkeletonBone(from: 3, to: 8), TMSkeletonBone(from: 8, to: 9),
            TMSkeletonBone(from: 2, to: 6), TMSkeletonBone(from: 3, to: 7), TMSkeletonBone(from: 6, to: 7),
        ],
        fills: [[2, 3, 7, 6]],
        head: TMFigureShape.Head(center: 0, sizeFrom: TMSkeletonBone(from: 2, to: 3)),
        widthFrom: TMSkeletonBone(from: 2, to: 3)
    )

    func pose(wrist: CGPoint, elbow: CGPoint) -> TMSkeletonPose {
        TMSkeletonPose(
            time: 0,
            points: [
                CGPoint(x: 0.5, y: 0.86), CGPoint(x: 0.5, y: 0.74),
                CGPoint(x: 0.42, y: 0.7), CGPoint(x: 0.58, y: 0.7),
                elbow, wrist,
                CGPoint(x: 0.44, y: 0.4), CGPoint(x: 0.56, y: 0.4),
                CGPoint(x: 0.6, y: 0.55), CGPoint(x: 0.61, y: 0.42),
            ]
        )
    }

    return TMPoseComparison(
        baseline: pose(wrist: CGPoint(x: 0.22, y: 0.6), elbow: CGPoint(x: 0.32, y: 0.65)),
        current: pose(wrist: CGPoint(x: 0.2, y: 0.8), elbow: CGPoint(x: 0.31, y: 0.75)),
        figure: figure,
        aspectRatio: 1,
        alignmentJoint: 1,
        emphasizedJoints: [2, 4, 5],
        accessibilityLabel: Text(verbatim: "Comparison")
    )
    .frame(width: 340)
    .padding(32)
}
#endif
