//
//  TherapyPopBurst.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 17/11/2026.
//

import SwiftUI

/// A short "bubble pops" celebration around a guide circle, played once per `trigger` change.
///
/// A ring in `tint` swells slightly and fades while droplets fly well beyond it and shrink, about half a
/// second in all. It draws nothing at rest, never blocks touches, and is hidden from
/// accessibility (the caller's completion sound and state already report the moment).
/// Reduce Motion keeps only a brief fading ring, without travel.
struct TMTherapyPopBurst: View {
    /// Change this value to play the burst once; the initial value plays nothing.
    let trigger: Int
    let diameter: CGFloat
    var tint: Color = TherapyPalette.guidanceOrange

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reduceMotion = reduceMotion
        let diameter = diameter
        let tint = tint

        Color.clear
            .frame(width: diameter, height: diameter)
            .keyframeAnimator(initialValue: BurstFrame.rest, trigger: trigger) { content, frame in
                content.overlay {
                    BurstShape(frame: frame, diameter: diameter, tint: tint, reduceMotion: reduceMotion)
                }
            } keyframes: { _ in
                KeyframeTrack(\.progress) {
                    MoveKeyframe(0)
                    CubicKeyframe(1, duration: reduceMotion ? 0.25 : 0.5)
                }
                KeyframeTrack(\.visible) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: reduceMotion ? 0.25 : 0.5)
                    MoveKeyframe(0)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The ring and droplets of one burst frame.
private struct BurstShape: View {
    let frame: BurstFrame
    let diameter: CGFloat
    let tint: Color
    let reduceMotion: Bool

    private static let dropletCount = 8

    var body: some View {
        let fade = (1 - frame.progress) * frame.visible

        ZStack {
            Circle()
                .stroke(tint, lineWidth: max(1, 8 * (1 - frame.progress)))
                .scaleEffect(1 + (reduceMotion ? 0.1 : 0.3) * frame.progress)
                .opacity(fade)

            if !reduceMotion {
                ForEach(0..<Self.dropletCount, id: \.self) { index in
                    droplet(index, fade: fade)
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func droplet(_ index: Int, fade: Double) -> some View {
        let angle = Double(index) / Double(Self.dropletCount) * 2 * .pi + .pi / 8
        // Droplets fly well past the swelling ring, so the circle reads as bursting apart.
        let distance = diameter / 2 * (1 + 1.2 * frame.progress)
        let size = max(2, diameter * 0.17 * (1 - 0.75 * frame.progress))

        return Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .offset(x: cos(angle) * distance, y: sin(angle) * distance)
            .opacity(fade)
    }
}

/// One frame of the burst: `progress` runs 0 → 1, `visible` hides the resting state.
private struct BurstFrame {
    var progress: Double
    var visible: Double

    static let rest = BurstFrame(progress: 1, visible: 0)
}
