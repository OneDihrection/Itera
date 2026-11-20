//
//  TherapyPopBurst.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 17/11/2026.
//

import SwiftUI

/// A short completion pulse around a guide circle, played once per `trigger` change.
///
/// The `completionPulse` Metal shader swells a soft glow in `tint` out from the circle's edge
/// twice, like a heartbeat, while the outline briefly brightens; about 0.7 s in all. It draws
/// nothing at rest, never blocks touches, and is hidden from accessibility (the caller's
/// completion sound and state already report the moment). Reduce Motion plays one short beat
/// with little travel.
struct TMTherapyPopBurst: View {
    /// Change this value to play the pulse once; the initial value plays nothing.
    let trigger: Int
    let diameter: CGFloat
    var tint: Color = TherapyPalette.guidanceOrange

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reduceMotion = reduceMotion
        let diameter = diameter
        let tint = tint
        let duration = reduceMotion ? 0.3 : 0.7

        Color.clear
            .frame(width: diameter, height: diameter)
            .keyframeAnimator(initialValue: BurstFrame.rest, trigger: trigger) { content, frame in
                content.overlay {
                    PulseLayer(frame: frame, diameter: diameter, tint: tint, reduceMotion: reduceMotion)
                }
            } keyframes: { _ in
                // Linear here: the shader eases each beat itself.
                KeyframeTrack(\.progress) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: duration)
                }
                KeyframeTrack(\.visible) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: duration)
                    MoveKeyframe(0)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The shader layer of one pulse frame, padded beyond the circle so the glow is never clipped
/// square.
private struct PulseLayer: View {
    let frame: BurstFrame
    let diameter: CGFloat
    let tint: Color
    let reduceMotion: Bool

    /// Matches `TMTherapyMergingGuide`'s outline, so the flash sits on the drawn ring.
    private var ringWidth: CGFloat {
        min(14, max(6, diameter * 0.17))
    }

    var body: some View {
        if frame.visible > 0 {
            let radius = diameter / 2
            // The farthest beat travels 35% of the radius and widens to 1.6 ring widths.
            let side = diameter + (radius * 0.35 + ringWidth * 2) * 2

            Rectangle()
                .fill(.black)
                .frame(width: side, height: side)
                .colorEffect(
                    ShaderLibrary.completionPulse(
                        .float2(Float(side), Float(side)),
                        .float(Float(radius)),
                        .float(Float(ringWidth)),
                        .float(Float(frame.progress)),
                        .float(reduceMotion ? 1 : 0),
                        .color(tint)
                    )
                )
        }
    }
}

/// One frame of the pulse: `progress` runs 0 → 1, `visible` hides the resting state.
private struct BurstFrame {
    var progress: Double
    var visible: Double

    static let rest = BurstFrame(progress: 1, visible: 0)
}
