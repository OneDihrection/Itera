//
//  SkeletonReplay.swift
//  Itera
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
        accessibilityLabel: Text
    ) {
        self.poses = poses
        self.bones = bones
        self.aspectRatio = aspectRatio
        self.mirrored = mirrored
        self.emphasizedJoints = emphasizedJoints
        self.emphasisColor = emphasisColor
        self.height = height
        self.accessibilityLabel = accessibilityLabel

        let duration = max(poses.last?.time ?? 0, 0.01)
        self.duration = duration
        _pausedTime = State(initialValue: duration / 2)
        bounds = Self.framing(poses, aspectRatio: aspectRatio, mirrored: mirrored)
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
            draw(pose(at: time), in: &context, size: size)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(TherapyPalette.progressPanel, in: RoundedRectangle(cornerRadius: 24))
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
    private static func place(_ point: CGPoint, aspectRatio: Double, mirrored: Bool) -> CGPoint {
        let x = point.x * aspectRatio
        return CGPoint(x: mirrored ? aspectRatio - x : x, y: 1 - point.y)
    }

    /// The padded union of every placed point, so the figure fills the frame for the whole replay.
    private static func framing(_ poses: [TMSkeletonPose], aspectRatio: Double, mirrored: Bool) -> CGRect {
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

        let padding = max(union.width, union.height, 0.05) * 0.12
        return union.insetBy(dx: -padding, dy: -padding)
    }
}
