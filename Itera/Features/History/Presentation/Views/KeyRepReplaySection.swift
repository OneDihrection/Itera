//
//  KeyRepReplaySection.swift
//  Itera
//
//  Created by dimaswisodewo on 13/11/2026.
//

import SwiftUI

/// The key-repetition replay shared by the movement and finger reports: a First / Hardest /
/// Last choice, a Video / Kerangka choice when the repetition has a clip, the replay itself and
/// one caption.
///
/// Repetitions recorded with the hand (fold towel, finger exercises) are drawn as a hand; the
/// rest as a body. The caller supplies which joints to emphasize and where clips are.
struct TMKeyRepReplaySection: View {
    /// The set's key repetitions, in repetition order.
    let reps: [KeyRep]
    /// Joint indices to emphasize for a repetition, in the skeleton drawn for it.
    let emphasizedJoints: (KeyRep) -> Set<Int>
    let clipURL: (KeyRep) -> URL?
    var isTrackingLow: (KeyRep) -> Bool = { _ in false }

    /// The hardest repetition is the one most worth a clinician's first look.
    static let defaultRole = KeyRepRole.hardest

    @State private var role: KeyRepRole?
    /// Clips are shown first when a repetition has one; the skeleton stays one tap away.
    @State private var showsSkeleton = false

    var body: some View {
        if let rep = selectedRep {
            VStack(alignment: .leading, spacing: 14) {
                rolePicker
                singleRepNote
                media(for: rep)

                Text(Self.caption(for: rep))
                    .typography(.body)
                    .foregroundStyle(TherapyPalette.muted)

                if isTrackingLow(rep) {
                    Label("history.report.lowTracking", systemImage: "eye.slash")
                        .typography(.subheadline)
                        .foregroundStyle(TherapyPalette.warning)
                }
            }
        }
    }

    // MARK: - Sections

    private var selectedRole: KeyRepRole {
        role ?? Self.defaultRole
    }

    /// The repetition holding the chosen role, falling back to the first recorded one.
    private var selectedRep: KeyRep? {
        reps.first { $0.roles.contains(selectedRole) } ?? reps.first
    }

    @ViewBuilder
    private var rolePicker: some View {
        if reps.count > 1 {
            Picker("history.report.chooseRep", selection: Binding(get: { selectedRole }, set: { role = $0 })) {
                ForEach(KeyRepRole.allCases, id: \.self) { role in
                    Text(LocalizedStringKey(role.titleKey)).tag(role)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// A set with one counted repetition (for example one directional-reach round) has no choice to
    /// offer, so say that this repetition is the first, hardest and last.
    @ViewBuilder
    private var singleRepNote: some View {
        if reps.count == 1, let rep = reps.first, rep.roles.count > 1 {
            Text("history.report.singleRep")
                .typography(.subheadline)
                .foregroundStyle(TherapyPalette.muted)
        }
    }

    @ViewBuilder
    private func media(for rep: KeyRep) -> some View {
        let clip = clipURL(rep)
        let label = Text("history.report.replayLabel \(rep.metrics.repNumber) \(Self.seconds(rep.metrics.duration))")

        if clip != nil {
            Picker("history.report.viewMode", selection: $showsSkeleton) {
                Text("history.report.viewVideo").tag(false)
                Text("history.report.viewSkeleton").tag(true)
            }
            .pickerStyle(.segmented)
        }

        // A new identity restarts playback when another repetition is chosen.
        if let clip, !showsSkeleton {
            TMRepClipPlayer(url: clip, accessibilityLabel: label)
                .id(clip)
        } else {
            skeleton(for: rep, label: label)
                .id(rep.metrics.repNumber)
        }
    }

    private func skeleton(for rep: KeyRep, label: Text) -> some View {
        let recordsHand = rep.frames.contains { $0.hand != nil }

        return TMSkeletonReplay(
            poses: rep.frames.map { recordsHand ? $0.handPose : $0.bodyPose },
            bones: recordsHand ? HandSkeleton.bones : BodyJoint.replayBones,
            aspectRatio: rep.aspectRatio,
            emphasizedJoints: emphasizedJoints(rep),
            height: 320,
            accessibilityLabel: label
        )
    }

    // MARK: - Wording

    private static func caption(for rep: KeyRep) -> LocalizedStringResource {
        let seconds = seconds(rep.metrics.duration)

        if let peak = rep.metrics.peakAngle {
            return "history.report.repCaptionPeak \(rep.metrics.repNumber) \(seconds) \(Int(peak.rounded()))"
        }

        if let fraction = rep.metrics.peakFraction {
            return "history.report.repCaptionRange \(rep.metrics.repNumber) \(seconds) \(Int((fraction * 100).rounded()))"
        }

        return "history.report.repCaption \(rep.metrics.repNumber) \(seconds)"
    }

    static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Presentation mapping

extension KeyRepRole {
    var titleKey: String {
        switch self {
        case .first: return "history.role.first"
        case .hardest: return "history.role.hardest"
        case .last: return "history.role.last"
        }
    }
}

private extension SkeletonFrame {
    var bodyPose: TMSkeletonPose {
        TMSkeletonPose(
            time: time,
            points: BodyJoint.allCases.map { joint in
                joints[joint].map { CGPoint(x: $0.x, y: $0.y) }
            }
        )
    }

    /// A frame without the hand draws nothing, so the replay shows the hand only where it was seen.
    var handPose: TMSkeletonPose {
        TMSkeletonPose(
            time: time,
            points: (hand ?? Array(repeating: nil, count: Self.handJointCount)).map { point in
                point.map { CGPoint(x: $0.x, y: $0.y) }
            }
        )
    }
}

extension BodyJoint {
    private static let replayPairs: [(BodyJoint, BodyJoint)] = [
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root), (.root, .leftHip), (.root, .rightHip),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    static let replayBones = replayPairs.map { TMSkeletonBone(from: $0.0.index, to: $0.1.index) }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    /// The trained limb, drawn emphasized; arm raise includes the hip it is measured against.
    /// Sit-to-stand emphasizes both legs and the trunk. `side` is the arm that moved in this
    /// repetition when both arms take turns.
    static func movingChain(for activity: SessionActivity, side: TherapySide?) -> Set<Int> {
        if activity.kind == .sitToStand {
            let body: [BodyJoint] = [
                .neck, .root, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
            ]
            return Set(body.map(\.index))
        }

        let left = (side ?? activity.side) == .left
        var joints: [BodyJoint] = left
            ? [.leftShoulder, .leftElbow, .leftWrist]
            : [.rightShoulder, .rightElbow, .rightWrist]

        if activity.kind == .armRaise {
            joints.append(left ? .leftHip : .rightHip)
        }

        return Set(joints.map(\.index))
    }
}

/// Bones and emphasis for the 21 hand joints in `HandPoseExtractor` order: wrist (0), then
/// thumb 1–4, index 5–8, middle 9–12, ring 13–16 and little 17–20, base to tip.
enum HandSkeleton {
    private static let fingerBases = [1, 5, 9, 13, 17]
    private static let fingertips = [4, 8, 12, 16, 20]
    private static let thumb = Set(1...4)
    private static let fingers = Set(5...20)
    private static let wholeHand = Set(0...20)

    static let bones: [TMSkeletonBone] = {
        var bones = fingerBases.map { TMSkeletonBone(from: 0, to: $0) }

        for base in fingerBases {
            for joint in base..<(base + 3) {
                bones.append(TMSkeletonBone(from: joint, to: joint + 1))
            }
        }

        // The knuckle line across the palm.
        bones += [(5, 9), (9, 13), (13, 17)].map { TMSkeletonBone(from: $0.0, to: $0.1) }
        return bones
    }()

    /// Opposition: the thumb and the fingertips it touches. Curl, spread and extension: the four
    /// fingers. Forearm rotation turns the whole hand.
    static func emphasis(for exercise: FingerExercise) -> Set<Int> {
        switch exercise {
        case .opposition:
            return thumb.union(fingertips)
        case .fullFist, .hookFist, .spreading, .extensionSequence:
            return fingers
        case .forearmRotation:
            return wholeHand
        }
    }

    /// Fold towel moves the whole hand.
    static let towelEmphasis = wholeHand
}
