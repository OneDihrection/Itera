//
//  SessionBubbleOverlay.swift
//  Tuntun
//
//  Created by dimaswisodewo on 17/11/2026.
//

import SwiftUI

/// A body exercise's start and target bubbles and the tracked joint, in normalized image
/// coordinates (0...1 on both axes, origin bottom-left, unmirrored).
struct SessionBubbleGuide {
    enum Zone { case start, target }
    let startCenter: CGPoint
    let targetCenter: CGPoint
    let trackedJoint: CGPoint?
    /// Bubble radius in normalized image height; acceptance uses the drawn radius.
    let radius: Double
    let activeZone: Zone
    let trackedJointInside: Bool
    let dwellProgress: Double
    /// The joint the limb turns around, such as the shoulder for an arm raise. When set, the arrow
    /// to the active bubble follows that turn instead of a gentle bow.
    var pivot: CGPoint? = nil
}

/// The body exercises' only camera guidance: the bubbles and the tracked joint, drawn with
/// `TMTherapyMergingGuide` so they match the finger and fold-towel indicators.
///
/// The 44 pt joint circle flows into the active bubble as it arrives and is one with it while the
/// joint is inside or a hold runs; the bubble never moves or grows, so the accepted boundary is
/// always the drawn outline. The other bubble is a quiet outline. Hold progress is the guide's arc,
/// and an accepted hold pops on its bubble. The guidance arrows (`TMSessionGuideArrows`) lie under
/// the circles. It draws no skeleton or text, and takes values only; holds, timing and tracking
/// stay with the caller.
struct TMSessionBubbleOverlay: View {
    /// Camera image width over height, so circles land on the visible picture.
    let imageAspect: Double
    let bubbleGuide: SessionBubbleGuide?
    /// Start and target share one bubble, which is the destination either way.
    var singleZone = false
    /// False draws only the target bubble, for exercises whose start is not a place to return to.
    var showsStart = true
    /// While a position is being captured: no active bubble and no joint circle.
    var settingUp = false
    /// A calibration hold on the joint itself, drawn as one circle with `holdProgress`.
    var captureJoint: CGPoint? = nil
    var holdProgress = 0.0
    /// The capture circle's radius in normalized image height; nil keeps 60 pt.
    var holdRadius: Double? = nil
    /// A lone joint marker, for guidance without bubbles such as a direction-only reach.
    var trackedJoint: CGPoint? = nil
    var movementCue: SessionMovementCue? = nil
    var reachArrow: SessionReachArrow? = nil
    /// Before practice starts (the countdown and its cue): every circle is a quiet outline with no
    /// hold arc or merge, so the patient sees where to move before the bubble becomes live.
    var preview = false
    let mirrored: Bool

    /// Counts accepted holds; each change plays the pop burst at `popSpot`.
    @State private var pops = 0
    /// The active bubble at the previous progress change.
    @State private var lastActive: (center: CGPoint, radius: Double)?
    /// Where the last accepted hold was.
    @State private var popSpot: (center: CGPoint, radius: Double)?

    /// The tracked joint's circle while it is apart from the bubble.
    private static let jointDiameter: CGFloat = 44
    private static let defaultHoldRadius: CGFloat = 60

    var body: some View {
        ZStack {
            TMSessionGuideArrows(
                imageAspect: imageAspect,
                approach: bubbleGuide,
                settingUp: settingUp,
                movementCue: movementCue,
                reachArrow: reachArrow,
                mirrored: mirrored
            )

            circles
                .opacity(preview ? 0.6 : 1)
        }
        .animation(.easeOut(duration: 0.35), value: preview)
        .onChange(of: bubbleGuide?.dwellProgress) { old, new in
            trackAcceptance(old: old, new: new)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var circles: some View {
        GeometryReader { proxy in
            if imageAspect > 0 {
                let mapping = Mapping(
                    geometry: CameraDisplayGeometry(aspect: imageAspect, viewport: proxy.size),
                    mirrored: mirrored
                )

                ZStack(alignment: .topLeading) {
                    jointMarker(mapping)
                    bubbles(mapping)
                    captureHold(mapping)
                    pop(mapping)
                }
            }
        }
    }

    /// Normalized image coordinates to the view, and normalized radii to points.
    private struct Mapping {
        let geometry: CameraDisplayGeometry
        let mirrored: Bool

        func point(_ point: CGPoint) -> CGPoint {
            geometry.point(point, mirrored: mirrored)
        }

        func length(_ value: Double) -> CGFloat {
            value * geometry.imageRect.height
        }
    }

    // MARK: - Acceptance

    /// The snapshot resets a hold's progress the moment it is accepted, so a drop from a nearly
    /// full arc is the acceptance cue. The accepted bubble is the one active before the drop,
    /// because acceptance may switch the snapshot to the other zone in the same update.
    private func trackAcceptance(old: Double?, new: Double?) {
        let accepted = lastActive

        if let guide = bubbleGuide {
            lastActive = (center(of: guide.activeZone, in: guide), guide.radius)
        }

        // The burst itself keeps only a brief ring under Reduce Motion.
        guard let old,
              old >= 0.85,
              (new ?? 0) < old,
              let spot = accepted ?? lastActive else {
            return
        }

        popSpot = spot
        pops += 1
    }

    // MARK: - Layers

    @ViewBuilder
    private func jointMarker(_ mapping: Mapping) -> some View {
        if let joint = trackedJoint ?? previewJoint {
            TMTherapyMergingGuide(
                center: mapping.point(joint),
                diameter: Self.jointDiameter,
                active: !preview
            )
        }
    }

    @ViewBuilder
    private func bubbles(_ mapping: Mapping) -> some View {
        if let guide = bubbleGuide {
            let diameter = mapping.length(guide.radius) * 2

            ForEach(quietZones(guide), id: \.self) { zone in
                TMTherapyMergingGuide(
                    center: mapping.point(center(of: zone, in: guide)),
                    diameter: diameter,
                    active: false
                )
            }

            if let zone = activeZone(guide) {
                activePair(guide, zone: zone, diameter: diameter, mapping: mapping)
            }
        }
    }

    @ViewBuilder
    private func activePair(
        _ guide: SessionBubbleGuide,
        zone: SessionBubbleGuide.Zone,
        diameter: CGFloat,
        mapping: Mapping
    ) -> some View {
        let bubble = mapping.point(center(of: zone, in: guide))

        if preview {
            TMTherapyMergingGuide(
                center: bubble,
                diameter: diameter,
                active: false
            )
        } else if let tracked = guide.trackedJoint {
            let joint = mapping.point(tracked)

            TMTherapyMergingGuide(
                first: joint,
                second: bubble,
                diameter: diameter,
                firstDiameter: Self.jointDiameter,
                merge: mergeAmount(guide, joint: joint, bubble: bubble, radius: diameter / 2),
                anchor: .second,
                progress: guide.dwellProgress,
                active: true,
                showsTimer: true
            )
        } else {
            TMTherapyMergingGuide(
                center: bubble,
                diameter: diameter,
                progress: guide.dwellProgress,
                active: true,
                showsTimer: true
            )
        }
    }

    @ViewBuilder
    private func captureHold(_ mapping: Mapping) -> some View {
        if let captureJoint {
            let radius = holdRadius.map(mapping.length) ?? Self.defaultHoldRadius

            TMTherapyMergingGuide(
                center: mapping.point(captureJoint),
                diameter: radius * 2,
                progress: holdProgress,
                active: true,
                showsTimer: true
            )
        }
    }

    /// Stays mounted, even before the first hold, so the first trigger change plays rather than
    /// mounting with it.
    private func pop(_ mapping: Mapping) -> some View {
        let radius = popSpot.map { mapping.length($0.radius) } ?? 0
        let center = popSpot.map { mapping.point($0.center) } ?? .zero

        return TMTherapyPopBurst(trigger: pops, diameter: max(1, radius * 2))
            .position(center)
    }

    /// The guide's joint, drawn apart from the bubble while previewing.
    private var previewJoint: CGPoint? {
        guard preview else {
            return nil
        }

        return bubbleGuide?.trackedJoint
    }

    // MARK: - Zones

    /// The bubble the joint should reach, if one is drawn and no position is being captured.
    private func activeZone(_ guide: SessionBubbleGuide) -> SessionBubbleGuide.Zone? {
        guard !settingUp else {
            return nil
        }

        if singleZone {
            return .start
        }

        if guide.activeZone == .start && !showsStart {
            return nil
        }

        return guide.activeZone
    }

    /// Drawn bubbles that are not the current destination: the saved start during setup, or the
    /// other end of the movement.
    private func quietZones(_ guide: SessionBubbleGuide) -> [SessionBubbleGuide.Zone] {
        var drawn: [SessionBubbleGuide.Zone] = []

        if showsStart || singleZone {
            drawn.append(.start)
        }

        if !settingUp && !singleZone {
            drawn.append(.target)
        }

        let active = activeZone(guide)

        return drawn.filter { $0 != active }
    }

    private func center(of zone: SessionBubbleGuide.Zone, in guide: SessionBubbleGuide) -> CGPoint {
        switch zone {
        case .start:
            return guide.startCenter
        case .target:
            return guide.targetCenter
        }
    }

    /// 1 while the joint counts as inside or a hold runs (including a larger exit radius once a
    /// hold starts), so credited time always shows one circle; otherwise a smoothstep from two
    /// bubble radii apart (0) to the drawn outline (1).
    private func mergeAmount(
        _ guide: SessionBubbleGuide,
        joint: CGPoint,
        bubble: CGPoint,
        radius: CGFloat
    ) -> Double {
        guard !guide.trackedJointInside,
              guide.dwellProgress == 0,
              radius > 0 else {
            return 1
        }

        let gap = hypot(joint.x - bubble.x, joint.y - bubble.y)
        let t = Double(min(1, max(0, (2 * radius - gap) / radius)))

        return t * t * (3 - 2 * t)
    }
}
