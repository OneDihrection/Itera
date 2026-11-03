//
//  SessionJointChainOverlay.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import SwiftUI

/// Draws tracked body joints as a connected chain over the camera image, with an optional caption
/// beside each joint. Points are normalized image coordinates with the origin at the bottom left.
struct SessionJointChainOverlay: View {
    struct Joint {
        let point: CGPoint
        var caption: String? = nil
        var highlighted = false
    }

    let imageSize: CGSize?
    let joints: [Joint]
    var color: Color = .green
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            guard let image = imageSize, image.width > 0, image.height > 0, joints.count > 1 else {
                return
            }
            let scale = min(size.width / image.width, size.height / image.height)
            let offset = CGPoint(
                x: (size.width - image.width * scale) / 2,
                y: (size.height - image.height * scale) / 2
            )
            func place(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: offset.x + (mirrored ? 1 - point.x : point.x) * image.width * scale,
                    y: offset.y + (1 - point.y) * image.height * scale
                )
            }
            let points = joints.map { place($0.point) }
            var path = Path()
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            // A dark underlay keeps the chain legible on bright rooms and skin tones.
            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            for (joint, center) in zip(joints, points) {
                let radius: CGFloat = joint.highlighted ? 13 : 10
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
                context.stroke(Path(ellipseIn: rect), with: .color(joint.highlighted ? .yellow : color), lineWidth: 5)
                if let caption = joint.caption {
                    let label = context.resolve(
                        Text(verbatim: caption).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    )
                    let anchor = CGPoint(x: center.x + radius + 10, y: center.y)
                    let background = CGRect(x: anchor.x - 6, y: anchor.y - 20, width: label.measure(in: size).width + 12, height: 40)
                    context.fill(Path(roundedRect: background, cornerRadius: 10), with: .color(.black.opacity(0.7)))
                    context.draw(label, at: anchor, anchor: .leading)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
