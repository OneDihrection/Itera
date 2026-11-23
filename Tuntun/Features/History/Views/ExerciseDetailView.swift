//
//  ExerciseDetailView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 23/11/2026.
//

import SwiftUI

/// The content of an exercise's detail panel, opened from a card on a day's progress page:
/// the day's three figures, its best repetition against an earlier session beside the
/// exercise's demonstration, the hardest
/// repetition's recording and the camera-estimate note. `TMDetailPanel` draws the card around it.
struct TMExerciseDetailView<ViewModel: ExerciseDetailViewModelProtocol>: View {
    @State private var viewModel: ViewModel
    @State private var confirmingRecordDelete = false

    @Environment(\.locale) private var locale

    init(viewModel: ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            title

            if let progress = viewModel.progress {
                content(progress)
            } else {
                status
            }
        }
        .foregroundStyle(TherapyPalette.ink)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Sections

    /// Yellow at the product owner's request, like the day page's title.
    private var title: some View {
        titleText
            .typography(size: 40, weight: .bold, relativeTo: .largeTitle)
            .foregroundStyle(TherapyPalette.brand)
            .fixedSize(horizontal: false, vertical: true)
            // Leaves room for the panel's close circle.
            .padding(.trailing, 56)
            .accessibilityAddTraits(.isHeader)
    }

    /// "Angkat lengan kiri" when the day practised one side, otherwise the plain name.
    private var titleText: Text {
        Text(verbatim: titleName)
    }

    private var titleName: String {
        let name = String(localized: String.LocalizationValue(viewModel.titleKey), bundle: AppLanguage.selected.resourceBundle)

        guard let side = viewModel.titleSide else {
            return name
        }

        let sideKey: String.LocalizationValue = side == .left ? "exerciseDetail.side.left" : "exerciseDetail.side.right"
        let sideName = String(localized: sideKey, bundle: AppLanguage.selected.resourceBundle)

        return String(
            localized: "exerciseDetail.title.sided \(name) \(sideName)",
            bundle: AppLanguage.selected.resourceBundle
        )
    }

    @ViewBuilder
    private var status: some View {
        if let key = viewModel.errorKey {
            TMTherapyError(key: key)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private func content(_ progress: ExerciseProgress) -> some View {
        if progress.sessionsOnDay.isEmpty {
            Text("exerciseDetail.empty")
                .typography(.body)
                .foregroundStyle(TherapyPalette.muted)
        } else {
            stats(progress)

            if showsProgress(progress) {
                TMDashedDivider()
                TMExerciseProgressSection(
                    viewModel: viewModel,
                    progress: progress,
                    wording: wording
                )
            }

            if let hardestRep = viewModel.keyRep(for: .hardest) {
                TMDashedDivider()
                TMExerciseRecordSection(
                    rep: hardestRep,
                    progress: progress,
                    baseline: viewModel.baseline,
                    baselineSession: viewModel.baselineSession,
                    wording: wording,
                    namesSet: viewModel.recordsSeveralSets,
                    deleteErrorKey: viewModel.clipDeleteErrorKey,
                    onDeleteClip: deleteClip
                )
            }
        }

        TMDashedDivider()

        Text("exerciseDetail.disclaimer")
            .typography(size: 18, weight: .regular, relativeTo: .footnote)
            .foregroundStyle(TherapyPalette.muted)
            .fixedSize(horizontal: false, vertical: true)

        if !progress.sessionsOnDay.isEmpty {
            recordDeletion(progress)
        }
    }

    // MARK: - Deleting the record

    /// "Hapus catatan latihan ini", confirmed first: deletes the exercise's sessions for the day
    /// with their replays, and the plan's done mark.
    @ViewBuilder
    private func recordDeletion(_ progress: ExerciseProgress) -> some View {
        TMTherapyButton(
            title: "exerciseDetail.deleteRecord",
            symbol: "trash",
            destructive: true,
            pill: true
        ) {
            confirmingRecordDelete = true
        }
        .fixedSize()
        .disabled(viewModel.deletingRecord)
        .confirmationDialog(
            "exerciseDetail.deleteRecord.title",
            isPresented: $confirmingRecordDelete,
            titleVisibility: .visible
        ) {
            Button("exerciseDetail.deleteRecord.confirm", role: .destructive) {
                Task {
                    await viewModel.deleteRecord()
                }
            }

            Button("exerciseDetail.record.deleteClip.cancel", role: .cancel) {}
        } message: {
            deletionMessage(progress)
        }

        if let key = viewModel.recordDeleteErrorKey {
            TMTherapyError(key: key)
        }
    }

    /// Names the exercise and day, and warns when a session also held other exercises.
    private func deletionMessage(_ progress: ExerciseProgress) -> Text {
        let day = progress.day.formatted(.dateTime.day().month(.wide).year().locale(locale))
        let message = Text("exerciseDetail.deleteRecord.message \(titleName) \(day)")

        guard viewModel.recordSharesSessions else {
            return message
        }

        return message
            + Text(verbatim: " ")
            + Text("exerciseDetail.deleteRecord.shared")
    }

    private var wording: ExerciseWording {
        ExerciseWording(exerciseID: viewModel.exerciseID, side: viewModel.titleSide)
    }

    private func deleteClip(of rep: RecordedRep) {
        Task {
            await viewModel.deleteClip(of: rep)
        }
    }

    /// Fold towel has no measure to compare, but still has pace and volume rows.
    private func showsProgress(_ progress: ExerciseProgress) -> Bool {
        progress.measure != .none
            || !progress.insights(against: viewModel.baselineSession).isEmpty
    }

    private func stats(_ progress: ExerciseProgress) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                statTiles(progress)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                statTiles(progress)
            }
        }
    }

    /// Each tile names its figure above the value and says, under a rule, what it measures, so
    /// a number is never shown without its meaning.
    @ViewBuilder
    private func statTiles(_ progress: ExerciseProgress) -> some View {
        peakTile(progress)

        TMDetailStatTile(
            value: progress.averageDuration.map(ExerciseDetailFormat.seconds) ?? Text(verbatim: "–"),
            caption: "exerciseDetail.stat.averageDuration",
            lines: [Text("exerciseDetail.stat.averageDuration.meaning")]
        )

        TMDetailStatTile(
            value: ExerciseDetailFormat.duration(progress.activeSeconds),
            caption: "exerciseDetail.stat.activeTime",
            lines: [Text("exerciseDetail.stat.activeTime.meaning")]
        )
    }

    /// The best repetition, or the repetition count for an exercise without a measure.
    @ViewBuilder
    private func peakTile(_ progress: ExerciseProgress) -> some View {
        switch progress.measure {
        case .angle:
            TMDetailStatTile(
                value: ExerciseDetailFormat.value(progress.peak, measure: .angle),
                caption: "exerciseDetail.stat.peakAngle",
                lines: [Text(wording.angleScaleKey)]
            )
        case .range:
            TMDetailStatTile(
                value: ExerciseDetailFormat.value(progress.peak, measure: .range),
                caption: "exerciseDetail.stat.peakRange",
                lines: [Text("exerciseDetail.stat.peakRange.meaning")]
            )
        case .none:
            TMDetailStatTile(
                value: Text(verbatim: "\(progress.repetitions)"),
                caption: "exerciseDetail.stat.repetitions",
                lines: [Text(wording.repetitionMeaningKey)]
            )
        }
    }
}

// MARK: - Progress

/// "Perkembangan gerakanmu": the baseline menu, the exercise's looping demonstration beside the
/// change in the exercise's own words, the best result of each session, and the insight rows.
private struct TMExerciseProgressSection<ViewModel: ExerciseDetailViewModelProtocol>: View {
    @Bindable var viewModel: ViewModel
    let progress: ExerciseProgress
    let wording: ExerciseWording

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            ViewThatFits(in: .horizontal) {
                // ViewThatFits measures unwrapped text; an explicit ideal width keeps the side-by-side
                // row whenever the panel is at least this wide, and lets the text wrap.
                HStack(alignment: .top, spacing: 32) {
                    picture
                        .frame(width: 340)

                    summary
                }
                .frame(idealWidth: 680, maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 20) {
                    picture
                        .frame(maxWidth: 340)

                    summary
                }
            }

            trend
                .padding(.top, 12)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("exerciseDetail.progress.title")
                .typography(size: 26, weight: .semiBold, relativeTo: .title2)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            baselineMenu
        }
    }

    /// "Dibandingkan dengan: Sesi pertama ⌃⌄". The prefix says the choice drives every
    /// comparison below; the value uses `action` rather than the Figma's light blue for contrast.
    private var baselineMenu: some View {
        Menu {
            Picker("exerciseDetail.baseline.label", selection: $viewModel.baseline) {
                ForEach(ProgressBaseline.allCases) { baseline in
                    Text(legendKey(baseline))
                        .tag(baseline)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("exerciseDetail.baseline.prefix")
                    .foregroundStyle(TherapyPalette.muted)

                Text(legendKey(viewModel.baseline))
                    .fontWeight(.semibold)
                    .foregroundStyle(TherapyPalette.action)

                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(TherapyPalette.action)
            }
            .typography(size: 20, weight: .regular, relativeTo: .body)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("exerciseDetail.baseline.label"))
        .accessibilityValue(Text(legendKey(viewModel.baseline)))
    }

    /// "Sesi pertama", the baseline's short name, as the legend and trend marker use it.
    private func legendKey(_ baseline: ProgressBaseline) -> LocalizedStringKey {
        LocalizedStringKey("exerciseDetail.legend." + baseline.rawValue)
    }

    /// The exercise's own demonstration, looping so the reader sees the whole movement.
    private var picture: some View {
        TMTherapyMediaPanel(padding: 12) {
            TMExerciseDetailDemonstration(
                exerciseID: viewModel.exerciseID,
                side: viewModel.titleSide
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The headline, since line and legend, then the insights card.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            change
            insights
        }
    }

    @ViewBuilder
    private var change: some View {
        if let baselineSession = viewModel.baselineSession,
           let change = progress.change(from: baselineSession) {
            comparison(change: change, baselineSession: baselineSession)
        } else if viewModel.baselineSession == nil {
            Text("exerciseDetail.progress.noBaseline")
                .typography(size: 20, weight: .regular, relativeTo: .body)
                .foregroundStyle(TherapyPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Each session's best result, the baseline and today marked; hidden below two points.
    @ViewBuilder
    private var trend: some View {
        let points = progress.trend(
            baseline: viewModel.baselineSession,
            limit: ExerciseProgress.trendLimit
        )

        if points.count >= 2 {
            TMTrendChart(
                title: "exerciseDetail.trend.title",
                points: points.enumerated().map { index, point in
                    trendPoint(point, index: index)
                },
                unit: progress.measure == .range ? "%" : "°",
                caption: Text(wording.trendHintKey)
            )
        }
    }

    private func trendPoint(_ point: ExerciseTrendPoint, index: Int) -> TMTrendPoint {
        let value = progress.measure == .range ? point.value * 100 : point.value

        if point.isDay {
            return TMTrendPoint(
                id: index,
                date: point.date,
                value: value,
                highlight: .current,
                marker: "exerciseDetail.legend.now"
            )
        }

        if point.isBaseline {
            return TMTrendPoint(
                id: index,
                date: point.date,
                value: value,
                highlight: .baseline,
                marker: LocalizedStringKey("exerciseDetail.legend." + viewModel.baseline.rawValue)
            )
        }

        return TMTrendPoint(id: index, date: point.date, value: value)
    }

    /// Pace, consistency, stamina and volume; they follow the baseline menu.
    @ViewBuilder
    private var insights: some View {
        let insights = progress.insights(against: viewModel.baselineSession)

        if !insights.isEmpty {
            TMInsightCard {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    row(for: insight)
                }
            }
        }
    }

    /// Each row leads with the aspect it describes ("Tempo", "Kestabilan"), so the sentence's
    /// number has a name.
    private func row(for insight: ExerciseInsight) -> TMInsightRow {
        switch insight {
        case .pace(let change):
            return TMInsightRow(
                text: ExerciseDetailFormat.pace(change, trend: progress.trend(ofDuration: change)),
                title: Text("exerciseDetail.insight.title.pace")
            )
        case .consistency(let spread):
            let level = progress.consistencyLevel(of: spread)

            return TMInsightRow(
                text: ExerciseDetailFormat.consistency(spread, measure: progress.measure, level: level),
                title: Text("exerciseDetail.insight.title.consistency"),
                tone: consistencyTone(level)
            )
        case .stamina(let change):
            let trend = progress.trend(of: change)

            return TMInsightRow(
                text: ExerciseDetailFormat.stamina(change, measure: progress.measure, trend: trend),
                title: Text("exerciseDetail.insight.title.stamina"),
                tone: trend == .lower ? .negative : .positive
            )
        case .volume(let repetitions, let change, let sessionsSince):
            return TMInsightRow(
                text: ExerciseDetailFormat.volume(repetitions: repetitions, change: change),
                title: Text("exerciseDetail.insight.title.volume"),
                detail: ExerciseDetailFormat.sessionsSince(sessionsSince, baseline: viewModel.baseline),
                tone: volumeTone(change)
            )
        }
    }

    /// Even peaks are green, a fair spread neutral, a wide one red.
    private func consistencyTone(_ level: ConsistencyLevel) -> TMInsightRow.Tone {
        switch level {
        case .even:
            return .positive
        case .fair:
            return .neutral
        case .varied:
            return .negative
        }
    }

    /// More repetitions than the baseline is green, fewer red, the same neutral.
    private func volumeTone(_ change: Int) -> TMInsightRow.Tone {
        if change > 0 {
            return .positive
        }

        if change < 0 {
            return .negative
        }

        return .neutral
    }

    private func comparison(change: Double, baselineSession: ExerciseSession) -> some View {
        let trend = progress.trend(of: change)

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ExerciseDetailFormat.headlineKey(trend))
                    .typography(size: 26, weight: .bold, relativeTo: .title2)

                Text(wording.leadKey)
                    .typography(size: 24, weight: .semiBold, relativeTo: .title3)

                ExerciseDetailFormat.change(
                    change,
                    measure: progress.measure,
                    trend: trend,
                    style: wording.style
                )
                .typography(size: 24, weight: .bold, relativeTo: .title3)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(sinceKey)
                .typography(size: 20, weight: .regular, relativeTo: .body)
                .foregroundStyle(TherapyPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            TMComparisonLegend(
                baselineTitle: Text(LocalizedStringKey("exerciseDetail.legend." + viewModel.baseline.rawValue)),
                baselineValue: ExerciseDetailFormat.value(progress.peak(of: baselineSession), measure: progress.measure),
                currentTitle: Text("exerciseDetail.legend.now"),
                currentValue: ExerciseDetailFormat.value(progress.peak, measure: progress.measure),
                change: ExerciseDetailFormat.signed(change, measure: progress.measure),
                changeFill: ExerciseDetailFormat.fill(trend)
            )
        }
        .accessibilityElement(children: .combine)
    }

    /// "Sejak latihan pertama hingga 9 November 2026".
    private var sinceKey: LocalizedStringKey {
        let day = progress.day.formatted(.dateTime.day().month(.wide).year().locale(locale))

        switch viewModel.baseline {
        case .firstSession:
            return "exerciseDetail.since.firstSession \(day)"
        case .previousSession:
            return "exerciseDetail.since.previousSession \(day)"
        case .weekAgo:
            return "exerciseDetail.since.weekAgo \(day)"
        }
    }
}

// MARK: - Demonstration

/// The exercise's demonstration, as the plan intro shows it, always looping (Reduce Motion
/// holds the target pose, as the players do everywhere). Arm clips follow the day's side;
/// with both sides practised they play as recorded.
private struct TMExerciseDetailDemonstration: View {
    let exerciseID: String
    let side: TherapySide?

    var body: some View {
        if let exercise = FingerExercise(rawValue: exerciseID) {
            TMFingerExampleView(
                exercise: exercise,
                phase: .demonstration,
                returning: false,
                finger: 0,
                side: side == .right ? .right : .left,
                paused: false
            )
        } else if let exercise = BalanceExercise(rawValue: exerciseID) {
            TMBalanceExerciseDemonstrationView(
                exercise: exercise,
                paused: false,
                arm: crossingArm
            )
        } else if let kind = TherapyKind(rawValue: exerciseID) {
            therapyDemonstration(kind)
        }
    }

    @ViewBuilder
    private func therapyDemonstration(_ kind: TherapyKind) -> some View {
        switch kind {
        case .foldTowel:
            TMTowelDemonstrationView()
        case .armRaise:
            movement(.armRaise)
        case .elbowBend:
            movement(.elbowBend)
        case .directionalReach:
            movement(.directionalReach)
        default:
            EmptyView()
        }
    }

    private func movement(_ asset: ExerciseAnimationAsset) -> some View {
        TMExerciseExample(
            asset: asset,
            mirrored: side == .right,
            mode: .looping
        )
    }

    private var crossingArm: CrossingArm? {
        switch side {
        case .left:
            return .left
        case .right:
            return .right
        case nil:
            return nil
        }
    }
}

// MARK: - Practice record

/// "Catatan latihan": the day's hardest repetition, as its clip or, by a switch, its skeleton,
/// with how long it took and how far it reached against the baseline. The first and last
/// repetitions are still recorded, but not shown here.
private struct TMExerciseRecordSection: View {
    /// The day's hardest recorded repetition.
    let rep: RecordedRep
    let progress: ExerciseProgress
    let baseline: ProgressBaseline
    let baselineSession: ExerciseSession?
    let wording: ExerciseWording
    /// The day recorded more than one set, so the heading names the repetition's set.
    let namesSet: Bool
    /// Set when the last clip deletion failed.
    let deleteErrorKey: String?
    let onDeleteClip: (RecordedRep) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSkeleton = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(rep)
            media(rep)
            clipActions(rep)
            callout(rep)
        }
    }

    // MARK: Header

    private func header(_ rep: RecordedRep) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text("exerciseDetail.record.title")
                .typography(size: 26, weight: .semiBold, relativeTo: .title2)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if rep.clipURL != nil {
                Toggle(isOn: skeletonBinding) {
                    Text("exerciseDetail.record.showSkeleton")
                        .typography(size: 18, weight: .regular, relativeTo: .body)
                        .foregroundStyle(TherapyPalette.ink)
                }
                .tint(TherapyPalette.brand)
                .fixedSize()
            }
        }
    }

    private var skeletonBinding: Binding<Bool> {
        Binding(
            get: {
                showsSkeleton
            },
            set: { value in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showsSkeleton = value
                }
            }
        )
    }

    private func callout(_ rep: RecordedRep) -> some View {
        TMHighlightCallout(heading: heading(rep)) {
            // Always one row; text wraps inside each tile and both keep the taller height.
            HStack(alignment: .top, spacing: 16) {
                tiles(rep)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Media

    @ViewBuilder
    private func media(_ rep: RecordedRep) -> some View {
        let metrics = rep.rep.metrics
        let label = Text("history.report.replayLabel \(metrics.repNumber) \(TMKeyRepReplaySection.seconds(metrics.duration))")

        // A new identity restarts playback when the repetition or the view mode changes.
        if let clip = rep.clipURL, !showsSkeleton {
            TMRepClipPlayer(url: clip, height: 420, accessibilityLabel: label)
                .id(clip)
                .transition(.opacity)
        } else {
            TMSkeletonReplay(
                poses: rep.rep.frames.map { rep.recordsHand ? $0.handPose : $0.bodyPose },
                bones: rep.recordsHand ? HandSkeleton.bones : BodyJoint.replayBones,
                aspectRatio: rep.rep.aspectRatio,
                emphasizedJoints: rep.emphasizedJoints,
                height: 360,
                figure: rep.recordsHand ? HandSkeleton.figureShape : BodyJoint.figureShape,
                accessibilityLabel: label
            )
            .id("\(metrics.repNumber)-skeleton")
            .transition(.opacity)
        }
    }

    // MARK: Clip deletion

    /// "Hapus video" under a shown clip, confirmed first; the skeleton and figures stay.
    @ViewBuilder
    private func clipActions(_ rep: RecordedRep) -> some View {
        if rep.clipURL != nil, !showsSkeleton {
            TMTherapyButton(
                title: "exerciseDetail.record.deleteClip",
                symbol: "trash",
                destructive: true,
                pill: true
            ) {
                confirmingDelete = true
            }
            .fixedSize()
            .confirmationDialog(
                "exerciseDetail.record.deleteClip.title",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("exerciseDetail.record.deleteClip.confirm", role: .destructive) {
                    onDeleteClip(rep)
                }

                Button("exerciseDetail.record.deleteClip.cancel", role: .cancel) {}
            } message: {
                Text("exerciseDetail.record.deleteClip.message")
            }
        }

        if let deleteErrorKey {
            TMTherapyError(key: deleteErrorKey)
        }
    }

    // MARK: Callout

    /// Plain words for a non-medical reader: "Di gerakan ke-5, gerakanmu sedikit berbeda. Yuk
    /// kita lihat!", the move in red. The set is named only when the day had more than one.
    private func heading(_ rep: RecordedRep) -> Text {
        let set = namesSet
            ? Text("exerciseDetail.callout.set \(rep.setNumber)")
            : Text(verbatim: "")

        return Text("exerciseDetail.callout.hardest.lead")
            + Text("exerciseDetail.callout.hardest.rep \(rep.rep.metrics.repNumber)")
                .foregroundStyle(TherapyPalette.warning)
            + set
            + Text("exerciseDetail.callout.hardest.tail")
    }

    @ViewBuilder
    private func tiles(_ rep: RecordedRep) -> some View {
        let metrics = rep.rep.metrics

        TMDetailStatTile(
            value: ExerciseDetailFormat.seconds(metrics.duration),
            caption: "exerciseDetail.callout.duration",
            lines: durationLines(metrics),
            fill: TherapyPalette.surface
        )

        if let peak = ExerciseDetailViewModel.peak(of: metrics, measure: progress.measure) {
            TMDetailStatTile(
                value: ExerciseDetailFormat.value(peak, measure: progress.measure),
                caption: wording.captionKey,
                lines: reachLines(peak),
                fill: TherapyPalette.surface
            )
        }
    }

    /// "Lebih lama dari biasanya (rata-rata 12,5 detik)", against the day's average.
    private func durationLines(_ metrics: RepMetrics) -> [Text] {
        guard let average = progress.averageDuration else {
            return []
        }

        let seconds = average.formatted(.number.precision(.fractionLength(1)))

        switch progress.trend(ofDuration: metrics.duration - average) {
        case .higher:
            return [Text("exerciseDetail.durationCompare.longer \(seconds)")]
        case .lower:
            return [Text("exerciseDetail.durationCompare.quicker \(seconds)")]
        case .steady:
            return [Text("exerciseDetail.durationCompare.same \(seconds)")]
        }
    }

    /// Against the baseline's best, coloured, then whether it was the day's best. The day's best
    /// value itself is not repeated: the first stat tile already shows it.
    private func reachLines(_ peak: Double) -> [Text] {
        var lines: [Text] = []

        if let baselineSession,
           let baselinePeak = progress.peak(of: baselineSession) {
            lines.append(baselineLine(change: peak - baselinePeak))
        }

        if let best = progress.peak, peak >= best {
            lines.append(Text("exerciseDetail.todayBest.this"))
        }

        return lines
    }

    /// "19° lebih rendah dari sesi pertama", or "Sama seperti sesi pertama".
    private func baselineLine(change: Double) -> Text {
        let trend = progress.trend(of: change)

        guard trend != .steady else {
            return Text(LocalizedStringKey("exerciseDetail.same." + baseline.rawValue))
        }

        return ExerciseDetailFormat.change(
            change,
            measure: progress.measure,
            trend: trend,
            style: wording.style
        )
            + Text(LocalizedStringKey("exerciseDetail.vs." + baseline.rawValue))
    }
}

// MARK: - Exercise wording

/// The exercise's own words for the progress headline and the record card, so a reader sees
/// "Lengan kirimu bisa terangkat 28° lebih tinggi" rather than a generic sentence. Exercises
/// without a measure, or without wording yet, fall back to the generic text.
private struct ExerciseWording {
    /// How a change reads: lifting is higher or lower, bending and turning further or less far,
    /// standing straighter or less straight.
    enum ChangeStyle {
        case lift
        case further
        case straight
    }

    let style: ChangeStyle
    /// The `exerciseDetail.lead.<group>` and `exerciseDetail.caption.<group>` group; nil uses
    /// the generic text.
    private let group: String?
    private let hasSide: Bool
    private let side: TherapySide?
    /// Fold towel counts a repetition as four folds.
    private let countsFolds: Bool

    init(exerciseID: String, side: TherapySide?) {
        self.side = side
        countsFolds = exerciseID == TherapyKind.foldTowel.rawValue

        switch exerciseID {
        case "armRaise":
            (group, style, hasSide) = ("arm", .lift, true)
        case "shoulderFlexion":
            (group, style, hasSide) = ("armForward", .lift, true)
        case "elbowBend":
            (group, style, hasSide) = ("elbow", .further, true)
        case "externalRotation":
            (group, style, hasSide) = ("rotateOut", .further, true)
        case "internalRotation":
            (group, style, hasSide) = ("rotateIn", .further, true)
        case "sitToStand":
            (group, style, hasSide) = ("stand", .straight, false)
        case "fullFist", "hookFist", "spreading", "extensionSequence":
            (group, style, hasSide) = ("fingers", .further, true)
        case "opposition":
            (group, style, hasSide) = ("thumb", .further, true)
        case "forearmRotation":
            (group, style, hasSide) = ("forearm", .further, true)
        default:
            (group, style, hasSide) = (nil, .lift, false)
        }
    }

    /// "Lengan kirimu bisa terangkat", "Lenganmu bisa terangkat" when the side is unknown.
    var leadKey: LocalizedStringKey {
        guard let group else {
            return "exerciseDetail.progress.lead"
        }

        // Built as a String first: an interpolated literal would become a format key.
        let key = "exerciseDetail.lead." + group + "." + sideSuffix

        return LocalizedStringKey(key)
    }

    /// "Seberapa tinggi lenganmu terangkat".
    var captionKey: LocalizedStringKey {
        guard let group else {
            return "exerciseDetail.callout.change"
        }

        return LocalizedStringKey("exerciseDetail.caption." + group)
    }

    /// What the peak angle measures. Only arm raise and elbow bend, whose angles
    /// `KeyRepRecorder` computes from known joints, say where 0° is; the Balancing engines'
    /// own estimates keep the generic line.
    var angleScaleKey: LocalizedStringKey {
        switch group {
        case "arm":
            return "exerciseDetail.scale.arm"
        case "elbow":
            return "exerciseDetail.scale.elbow"
        default:
            return "exerciseDetail.scale.angle"
        }
    }

    /// "Garis naik berarti lenganmu terangkat makin tinggi", under the trend's title.
    var trendHintKey: LocalizedStringKey {
        guard group != nil else {
            return "exerciseDetail.trendHint.generic"
        }

        switch style {
        case .lift:
            return "exerciseDetail.trendHint.lift"
        case .further:
            return "exerciseDetail.trendHint.further"
        case .straight:
            return "exerciseDetail.trendHint.straight"
        }
    }

    /// What one counted repetition is, for an exercise without a measure.
    var repetitionMeaningKey: LocalizedStringKey {
        countsFolds
            ? "exerciseDetail.stat.repetitions.towel"
            : "exerciseDetail.stat.repetitions.meaning"
    }

    private var sideSuffix: String {
        guard hasSide, let side else {
            return "none"
        }

        return side.rawValue
    }
}

// MARK: - Wording

/// Formatting shared by the panel's sections. Angles are camera estimates, so they are whole
/// degrees; ranges are whole percentages of the calibrated range.
private enum ExerciseDetailFormat {
    static func value(_ value: Double?, measure: ExerciseMeasure) -> Text {
        guard let value else {
            return Text(verbatim: "–")
        }

        switch measure {
        case .angle:
            return Text(verbatim: "≈ \(Int(value.rounded()))°")
        case .range:
            return Text(verbatim: "\(Int((value * 100).rounded()))%")
        case .none:
            return Text(verbatim: "–")
        }
    }

    /// The legend pill: "+28°", "−19°", "+12%".
    static func signed(_ change: Double, measure: ExerciseMeasure) -> Text {
        let amount = measure == .range ? Int((change * 100).rounded()) : Int(change.rounded())
        let sign = amount > 0 ? "+" : (amount < 0 ? "−" : "±")
        let unit = measure == .range ? "%" : "°"

        return Text(verbatim: "\(sign)\(abs(amount))\(unit)")
    }

    /// The change in the exercise's words: "28° lebih tinggi" or "12° lebih jauh" in green,
    /// "19° lebih rendah" in red, or "about the same".
    static func change(
        _ change: Double,
        measure: ExerciseMeasure,
        trend: ProgressTrend,
        style: ExerciseWording.ChangeStyle
    ) -> Text {
        let amount = measure == .range
            ? abs(Int((change * 100).rounded()))
            : abs(Int(change.rounded()))

        switch trend {
        case .steady:
            return Text("exerciseDetail.change.steady")
                .foregroundStyle(TherapyPalette.ink)
        case .higher:
            return higherText(amount, measure: measure, style: style)
                .foregroundStyle(TherapyPalette.green)
        case .lower:
            return lowerText(amount, measure: measure, style: style)
                .foregroundStyle(TherapyPalette.warning)
        }
    }

    private static func higherText(_ amount: Int, measure: ExerciseMeasure, style: ExerciseWording.ChangeStyle) -> Text {
        guard measure != .range else {
            return Text("exerciseDetail.change.rangeHigher \(amount)")
        }

        switch style {
        case .lift:
            return Text("exerciseDetail.change.angleHigher \(amount)")
        case .further:
            return Text("exerciseDetail.change.further.higher \(amount)")
        case .straight:
            return Text("exerciseDetail.change.straight.higher \(amount)")
        }
    }

    private static func lowerText(_ amount: Int, measure: ExerciseMeasure, style: ExerciseWording.ChangeStyle) -> Text {
        guard measure != .range else {
            return Text("exerciseDetail.change.rangeLower \(amount)")
        }

        switch style {
        case .lift:
            return Text("exerciseDetail.change.angleLower \(amount)")
        case .further:
            return Text("exerciseDetail.change.further.lower \(amount)")
        case .straight:
            return Text("exerciseDetail.change.straight.lower \(amount)")
        }
    }

    /// Pace is worded neutrally: quicker is not always better in therapy.
    static func pace(_ change: Double, trend: ProgressTrend) -> Text {
        let seconds = abs(change).formatted(.number.precision(.fractionLength(1)))

        switch trend {
        case .higher:
            return Text("exerciseDetail.insight.paceSlower \(seconds)")
        case .lower:
            return Text("exerciseDetail.insight.paceFaster \(seconds)")
        case .steady:
            return Text("exerciseDetail.insight.paceSteady")
        }
    }

    static func consistency(_ spread: Double, measure: ExerciseMeasure, level: ConsistencyLevel) -> Text {
        let amount = whole(spread, measure: measure)

        switch (level, measure) {
        case (.even, .range):
            return Text("exerciseDetail.insight.evenRange \(amount)")
        case (.even, _):
            return Text("exerciseDetail.insight.evenAngle \(amount)")
        case (.fair, .range):
            return Text("exerciseDetail.insight.fairRange \(amount)")
        case (.fair, _):
            return Text("exerciseDetail.insight.fairAngle \(amount)")
        case (.varied, .range):
            return Text("exerciseDetail.insight.variedRange \(amount)")
        case (.varied, _):
            return Text("exerciseDetail.insight.variedAngle \(amount)")
        }
    }

    static func stamina(_ change: Double, measure: ExerciseMeasure, trend: ProgressTrend) -> Text {
        let amount = whole(abs(change), measure: measure)

        switch (trend, measure) {
        case (.steady, _):
            return Text("exerciseDetail.insight.staminaSteady")
        case (.higher, .range):
            return Text("exerciseDetail.insight.staminaHigherRange \(amount)")
        case (.higher, _):
            return Text("exerciseDetail.insight.staminaHigherAngle \(amount)")
        case (.lower, .range):
            return Text("exerciseDetail.insight.staminaLowerRange \(amount)")
        case (.lower, _):
            return Text("exerciseDetail.insight.staminaLowerAngle \(amount)")
        }
    }

    static func volume(repetitions: Int, change: Int) -> Text {
        if change > 0 {
            return Text("exerciseDetail.insight.volumeMore \(repetitions) \(change)")
        }

        if change < 0 {
            return Text("exerciseDetail.insight.volumeFewer \(repetitions) \(-change)")
        }

        return Text("exerciseDetail.insight.volumeSame \(repetitions)")
    }

    static func sessionsSince(_ count: Int, baseline: ProgressBaseline) -> Text {
        switch baseline {
        case .firstSession:
            return Text("exerciseDetail.insight.sessionsSinceFirst \(count)")
        case .previousSession:
            return Text("exerciseDetail.insight.sessionsSincePrevious \(count)")
        case .weekAgo:
            return Text("exerciseDetail.insight.sessionsSinceWeekAgo \(count)")
        }
    }

    /// Whole degrees, or whole percentage points of the calibrated range.
    private static func whole(_ value: Double, measure: ExerciseMeasure) -> Int {
        measure == .range ? Int((value * 100).rounded()) : Int(value.rounded())
    }

    static func headlineKey(_ trend: ProgressTrend) -> LocalizedStringKey {
        switch trend {
        case .higher:
            return "exerciseDetail.headline.higher"
        case .steady:
            return "exerciseDetail.headline.steady"
        case .lower:
            return "exerciseDetail.headline.lower"
        }
    }

    static func fill(_ trend: ProgressTrend) -> Color {
        switch trend {
        case .higher:
            return TherapyPalette.green
        case .steady:
            return TherapyPalette.action
        case .lower:
            return TherapyPalette.warning
        }
    }

    /// "12,5 detik".
    static func seconds(_ value: Double) -> Text {
        Text("exerciseDetail.seconds \(value.formatted(.number.precision(.fractionLength(1))))")
    }

    /// "1 mnt 40 dtk", or "40 dtk" under a minute.
    static func duration(_ seconds: Double) -> Text {
        let total = Int(seconds.rounded())

        guard total >= 60 else {
            return Text("exerciseDetail.secondsShort \(total)")
        }

        return Text("exerciseDetail.minutesSeconds \(total / 60) \(total % 60)")
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockExerciseDetailViewModel: ExerciseDetailViewModelProtocol {
    let exerciseID = "armRaise"
    let titleKey = "session.armRaise"
    let recordsSeveralSets = false
    let clipDeleteErrorKey: String? = nil
    let titleSide: TherapySide? = .left
    let day = Calendar.current.startOfDay(for: .now)
    let loading = false
    let errorKey: String? = nil
    let progress: ExerciseProgress?
    var baseline: ProgressBaseline = .firstSession

    func keyRep(for role: KeyRepRole) -> RecordedRep? {
        nil
    }

    init(withBaseline: Bool) {
        let today = Calendar.current.startOfDay(for: .now).addingTimeInterval(10 * 3600)
        let peaks: [Double] = [108, 112, 104, 110, 97]
        let metrics = peaks.enumerated().map { index, peak in
            RepMetrics(
                repNumber: index + 1,
                duration: 10 + Double(index),
                startAngle: 20,
                peakAngle: peak,
                trackingCoverage: 1
            )
        }
        var sessions = [
            ExerciseSession(date: today, report: .session(UUID()), side: .left, repetitions: 5, activeSeconds: 100, metrics: metrics),
        ]

        if withBaseline {
            let earlierPeaks: [Double] = [84, 90, 88, 97, 104]

            for (index, peak) in earlierPeaks.enumerated() {
                let date = today.addingTimeInterval(-Double(15 - index * 3) * 24 * 3600)
                let earlierMetrics = [
                    RepMetrics(repNumber: 1, duration: 14, startAngle: 20, peakAngle: peak, trackingCoverage: 1),
                ]

                sessions.append(
                    ExerciseSession(date: date, report: .session(UUID()), side: .left, repetitions: 3, activeSeconds: 42, metrics: earlierMetrics)
                )
            }
        }

        progress = ExerciseProgress(sessions: sessions, day: today)
    }

    var baselineSession: ExerciseSession? {
        progress?.baselineSession(baseline)
    }

    let deletingRecord = false
    let recordDeleteErrorKey: String? = nil
    let recordSharesSessions = false

    func load() async {}
    func deleteClip(of rep: RecordedRep) async {}
    func deleteRecord() async {}
    func close() {}
}

#Preview("Exercise detail") {
    TMDetailPanel(closeTitle: "action.close", onClose: {}) {
        TMExerciseDetailView(viewModel: MockExerciseDetailViewModel(withBaseline: true))
    }
}

#Preview("Exercise detail, first practice") {
    TMDetailPanel(closeTitle: "action.close", onClose: {}) {
        TMExerciseDetailView(viewModel: MockExerciseDetailViewModel(withBaseline: false))
    }
}
#endif
