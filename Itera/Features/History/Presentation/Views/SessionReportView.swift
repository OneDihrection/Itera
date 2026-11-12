//
//  SessionReportView.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import SwiftUI

/// One arm-practice session for a clinician, kept to a low reading load: per set one sentence,
/// three numbers and one replay, with the rest behind disclosures.
struct TMSessionReportView: View {
    @State var model: SessionReportViewModel
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                status
                ForEach(model.results, id: \.executionID) { result in
                    TMSetReportSection(result: result, model: model)
                }
                footer
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas)
        .navigationTitle("history.report.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.startedAt, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .typography(.headline)
                    .foregroundStyle(TherapyPalette.muted)
                Text("history.report.title")
                    .typography(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if model.loading, model.summary == nil {
            ProgressView()
                .frame(maxWidth: .infinity)
        }

        if let key = model.errorKey {
            TMTherapyError(key: key)
            TMTherapyButton(title: "action.retry", secondary: true, pill: true) {
                Task { await model.load() }
            }
        }

        if model.replaysUnavailable {
            Text("history.report.replaysUnavailable")
                .typography(.body)
                .foregroundStyle(TherapyPalette.muted)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.summary != nil {
            DisclosureGroup("history.report.aboutMeasurement") {
                Text("history.report.disclaimer")
                    .typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }
            .typography(.body)
            .tint(TherapyPalette.brand)

            TMTherapyButton(title: "history.report.delete", symbol: "trash", secondary: true, pill: true) {
                Task {
                    if await model.delete() {
                        router.pop()
                    }
                }
            }
        }
    }
}

// MARK: - One set

private struct TMSetReportSection: View {
    let result: SessionActivityResult
    let model: SessionReportViewModel
    @State private var role: KeyRepRole?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headline
            metrics
            replay
            details
        }
    }

    /// The terracotta card: what was practiced and the one sentence worth reading.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
                .typography(size: 32, weight: .bold, relativeTo: .title)
                .accessibilityAddTraits(.isHeader)

            if result.activity.sets > 1 {
                Text("session.setProgress \(result.setNumber ?? 1) \(result.activity.sets)")
                    .typography(size: 20, weight: .medium, relativeTo: .title3)
            }

            if let sentence = model.headline(for: result) {
                Text(sentence)
                    .typography(size: 22, weight: .medium, relativeTo: .title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(TherapyPalette.onBrand)
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TherapyPalette.brand, in: RoundedRectangle(cornerRadius: 26))
    }

    private var title: Text {
        result.activity.reportTitle
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                repetitionsMetric
                Divider().frame(height: 64)
                peakMetric
                Divider().frame(height: 64)
                durationMetric
            }

            VStack(spacing: 18) {
                repetitionsMetric
                peakMetric
                durationMetric
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background(TherapyPalette.progressPanel, in: RoundedRectangle(cornerRadius: 24))
    }

    private var repetitionsMetric: some View {
        TMTherapyProgressMetric(
            icon: "repeat",
            value: Text(verbatim: "\(result.completedWork) / \(result.activity.goal)"),
            title: "progress.repetitionUnit"
        )
    }

    private var peakMetric: some View {
        TMTherapyProgressMetric(
            icon: "angle",
            value: model.highestPeak(for: result).map { Text(verbatim: "≈ \(Int($0.rounded()))°") } ?? Text(verbatim: "–"),
            title: LocalizedStringKey(model.peakTitleKey(for: result))
        )
    }

    private var durationMetric: some View {
        TMTherapyProgressMetric(
            icon: "clock",
            value: model.averageDuration(for: result).map { Text("history.report.seconds \(Self.seconds($0))") } ?? Text(verbatim: "–"),
            title: "history.report.averageDuration"
        )
    }

    // MARK: Replay

    @ViewBuilder
    private var replay: some View {
        let reps = model.keyReps(for: result)
        let selectedRole = role ?? model.defaultRole

        if let rep = model.keyRep(selectedRole, for: result) {
            VStack(alignment: .leading, spacing: 14) {
                if reps.count > 1 {
                    Picker("history.report.chooseRep", selection: Binding(get: { selectedRole }, set: { role = $0 })) {
                        ForEach(KeyRepRole.allCases, id: \.self) { role in
                            Text(LocalizedStringKey(role.titleKey)).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                TMSkeletonReplay(
                    poses: rep.frames.map(\.pose),
                    bones: BodyJoint.replayBones,
                    aspectRatio: rep.aspectRatio,
                    emphasizedJoints: BodyJoint.movingChain(for: result.activity, side: rep.metrics.side),
                    height: 320,
                    accessibilityLabel: Text("history.report.replayLabel \(rep.metrics.repNumber) \(Self.seconds(rep.metrics.duration))")
                )
                // A new identity restarts playback when another repetition is chosen.
                .id(rep.metrics.repNumber)

                Text(caption(for: rep))
                    .typography(.body)
                    .foregroundStyle(TherapyPalette.muted)

                if model.isTrackingLow(rep) {
                    Label("history.report.lowTracking", systemImage: "eye.slash")
                        .typography(.subheadline)
                        .foregroundStyle(TherapyPalette.warning)
                }
            }
        } else if !model.replaysUnavailable {
            Text("history.report.noReplays")
                .typography(.body)
                .foregroundStyle(TherapyPalette.muted)
        }
    }

    private func caption(for rep: KeyRep) -> LocalizedStringResource {
        let seconds = Self.seconds(rep.metrics.duration)

        guard let peak = rep.metrics.peakAngle else {
            return "history.report.repCaption \(rep.metrics.repNumber) \(seconds)"
        }

        return "history.report.repCaptionPeak \(rep.metrics.repNumber) \(seconds) \(Int(peak.rounded()))"
    }

    // MARK: Details

    @ViewBuilder
    private var details: some View {
        let metrics = result.repMetrics ?? []
        let notes = model.notes(for: result)

        if metrics.count > 1 || notes.count > 1 {
            DisclosureGroup("history.report.repDetails") {
                VStack(alignment: .leading, spacing: 16) {
                    if metrics.contains(where: { $0.peakAngle != nil }) {
                        TMRepValueChart(
                            title: "history.report.peakAngle",
                            values: metrics.map { metric in
                                TMRepValue(
                                    repNumber: metric.repNumber,
                                    value: metric.peakAngle,
                                    marker: marker(for: metric.repNumber)
                                )
                            },
                            unit: "°"
                        )
                    }

                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .typography(.body)
                    }
                }
                .padding(.top, 12)
            }
            .typography(.body)
            .tint(TherapyPalette.brand)
        }
    }

    /// The key-repetition role shown above a bar, so emphasis is never color alone.
    private func marker(for repNumber: Int) -> LocalizedStringKey? {
        let reps = model.keyReps(for: result)

        guard let role = reps.first(where: { $0.metrics.repNumber == repNumber })?.roles.first else {
            return nil
        }

        return LocalizedStringKey(role.titleKey)
    }

    private static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Presentation mapping

private extension KeyRepRole {
    var titleKey: String {
        switch self {
        case .first: return "history.role.first"
        case .hardest: return "history.role.hardest"
        case .last: return "history.role.last"
        }
    }
}

extension SessionActivity {
    /// "Exercise · Side": both sides when arms took turns, no side for sit-to-stand.
    var reportTitle: Text {
        let name = Text(LocalizedStringKey(kind.titleKey))

        guard hasSide else {
            return name
        }

        let sideKey: LocalizedStringKey = alternatesSides
            ? "history.bothSides"
            : (side == .left ? "session.left" : "session.right")

        return name + Text(verbatim: " · ") + Text(sideKey)
    }
}

extension TherapyKind {
    /// The localized exercise name used by sessions, history and reports. Balancing exercises
    /// reuse their own screen titles.
    var titleKey: String {
        switch self {
        case .armRaise: return "session.armRaise"
        case .elbowBend: return "session.elbowBend"
        case .directionalReach: return "session.directionalReach"
        case .foldTowel: return "session.foldTowel"
        case .sitToStand: return "session.sitToStand"
        case .crossMidline, .externalRotation, .internalRotation, .shoulderFlexion:
            return BalanceExercise(kind: self)?.key("title") ?? rawValue
        }
    }

    /// The SF Symbol shown beside the exercise in history.
    var symbolName: String {
        switch self {
        case .armRaise, .externalRotation, .internalRotation, .shoulderFlexion: return "figure.arms.open"
        case .elbowBend: return "figure.strengthtraining.traditional"
        case .directionalReach: return "hand.point.up.left"
        case .foldTowel: return "square.stack.3d.up"
        case .sitToStand: return "figure.stand"
        case .crossMidline: return "figure.cross.training"
        }
    }
}

private extension SkeletonFrame {
    var pose: TMSkeletonPose {
        TMSkeletonPose(
            time: time,
            points: BodyJoint.allCases.map { joint in
                joints[joint].map { CGPoint(x: $0.x, y: $0.y) }
            }
        )
    }
}

private extension BodyJoint {
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
