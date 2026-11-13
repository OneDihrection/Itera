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

                if showsPeak {
                    Divider().frame(height: 64)
                    peakMetric
                }

                Divider().frame(height: 64)
                durationMetric
            }

            VStack(spacing: 18) {
                repetitionsMetric

                if showsPeak {
                    peakMetric
                }

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

    /// Fold towel has no angle, so its tile would only ever show a dash.
    private var showsPeak: Bool {
        result.activity.kind != .foldTowel
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

        if !reps.isEmpty {
            TMKeyRepReplaySection(
                reps: reps,
                emphasizedJoints: emphasizedJoints(for:),
                clipURL: { model.clipURL(for: $0, in: result) },
                isTrackingLow: model.isTrackingLow
            )
        } else if !model.replaysUnavailable {
            Text("history.report.noReplays")
                .typography(.body)
                .foregroundStyle(TherapyPalette.muted)
        }
    }

    /// Fold towel records the hand; every other exercise records the body.
    private func emphasizedJoints(for rep: KeyRep) -> Set<Int> {
        guard result.activity.kind != .foldTowel else {
            return HandSkeleton.towelEmphasis
        }

        return BodyJoint.movingChain(for: result.activity, side: rep.metrics.side)
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
