//
//  FingerReportsView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

/// The Progress tab presents the current week, repetition totals and saved practice. It owns the
/// tab's navigation stack.
struct TMFingerReportsView<ViewModel: ReportsViewModelProtocol, Builder: HistoryContentBuildable>: View {
    @State private var viewModel: ViewModel
    private let builder: Builder

    @Environment(\.locale) private var locale
    @State private var confirmingHistoryDeletion = false

    init(viewModel: ViewModel, builder: Builder) {
        _viewModel = State(initialValue: viewModel)
        self.builder = builder
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            content
                .navigationDestination(for: HistoryRoute.self) { route in
                    destination(route)
                }
        }
    }

    @ViewBuilder
    private func destination(_ route: HistoryRoute) -> some View {
        switch route {
        case .fingerReport(let id):
            builder.buildFingerReport(id: id)
        case .sessionReport(let id):
            builder.buildSessionReport(id: id)
        }
    }

    private var content: some View {
        let report = PracticeReport(history: viewModel.fingerHistory)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                weekSummary(report)

                Divider()
                latestSection(report.currentWeek.first)

                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("progress.weeklyChart")
                    chart(report.weeklyRepetitions)
                }

                Divider()
                historySection(historyEntries(report.sessions))
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).typography(.title2).accessibilityAddTraits(.isHeader)
    }

    private func latestSection(_ latest: FingerSessionSummary?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("progress.latestThisWeek")
            if let latest {
                sessionCard(latest)
            } else {
                Text("progress.noSessionThisWeek")
                    .typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekSummary(_ report: PracticeReport) -> some View {
        let sessions = report.currentWeek
        let repetitions = sessions.reduce(0) { $0 + $1.totalRepetitions }
        let minutes = PracticeReport.minutes(sessions.reduce(0) { $0 + $1.duration })
        let activeDays = report.days.filter { date in
            report.sessionsByDay[date, default: []].contains { $0.totalRepetitions > 0 || $0.duration > 0 }
        }.count

        return TMTherapyWeekSummary(
            title: "progress.weekDays \(activeDays)",
            detail: "progress.weekDetail \(sessions.count) \(repetitions) \(minutes)",
            days: report.days.map { date in
                dayCell(date, sessions: report.sessionsByDay[date, default: []])
            }
        ) {
            if let latest = sessions.first {
                sessionCard(latest, centeredDate: true)
            }
        }
    }

    private func dayCell(_ date: Date, sessions: [FingerSessionSummary]) -> TherapyProgressDay {
        let completed = sessions.count { $0.outcome == .completed }
        let caption: LocalizedStringKey
        let status: TherapyProgressDay.Status

        if completed > 0, completed == sessions.count {
            caption = "progress.daySessions \(completed)"
            status = .done
        } else if !sessions.isEmpty {
            caption = "progress.dayPartial \(sessions.count - completed)"
            status = .partial
        } else {
            caption = "progress.dayEmpty"
            status = .empty
        }

        return TherapyProgressDay(
            id: date,
            label: date.formatted(.dateTime.day().month(.abbreviated).locale(locale)),
            caption: caption,
            status: status
        )
    }

    private func sessionCard(_ session: FingerSessionSummary, centeredDate: Bool = false) -> some View {
        TMTherapyProgressSessionCard(
            date: session.ended,
            completed: session.results.count { $0.completed && !$0.skipped },
            planned: session.routine.exercises.count,
            minutes: PracticeReport.minutes(session.duration),
            repetitions: session.totalRepetitions,
            centeredDate: centeredDate
        )
    }

    private func chart(_ repetitions: [Int]) -> some View {
        let labels: [LocalizedStringKey] = [
            "progress.threeWeeksAgo", "progress.twoWeeksAgo", "progress.lastWeek", "progress.thisWeek"
        ]
        let completedWeeks = repetitions.dropLast()
        let increased = (completedWeeks.first ?? 0) < (completedWeeks.last ?? 0)

        return TMTherapyWeeklyRepetitionChart(
            headline: increased ? "progress.chartIncreased" : "progress.chartHeadline",
            bars: zip(labels, repetitions).enumerated().map { index, pair in
                .init(id: index, title: pair.0, repetitions: pair.1)
            }
        )
    }

    /// Finger and arm sessions, newest first.
    private func historyEntries(_ finger: [FingerSessionSummary]) -> [HistoryEntry] {
        let arm = viewModel.armHistory

        return (finger.map(HistoryEntry.finger) + arm.map(HistoryEntry.arm))
            .sorted { $0.date > $1.date }
    }

    private func historySection(_ sessions: [HistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline) {
                sectionTitle("reports.history")
                Spacer(minLength: 12)
                Text("progress.sessionsRecorded \(sessions.count)")
                    .typography(.subheadline)
                    .foregroundStyle(TherapyPalette.muted)
            }

            if let error = viewModel.errorKey {
                TMTherapyError(key: error)
                TMTherapyButton(title: "action.retry", secondary: true, pill: true) {
                    Task { await viewModel.refresh() }
                }
            } else if sessions.isEmpty {
                Text("reports.emptyDetail").typography(.body).foregroundStyle(TherapyPalette.muted)
            }

            if !sessions.isEmpty {
                historyDeletionControls
            }

            ForEach(sessions) { entry in
                builder.buildCell(entry: entry)
            }
        }
    }

    private var historyDeletionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if confirmingHistoryDeletion {
                Text("progress.deleteHistoryMessage").typography(.body)
                HStack {
                    TMTherapyButton(title: "progress.cancelHistoryDeletion", secondary: true, disabled: viewModel.deletingHistory) {
                        confirmingHistoryDeletion = false
                    }
                    TMTherapyButton(title: "progress.deleteHistory", destructive: true, disabled: viewModel.deletingHistory) {
                        Task { await deleteHistory() }
                    }
                }
            } else {
                TMTherapyTextButton(title: "progress.deleteHistory") {
                    confirmingHistoryDeletion = true
                }
            }
        }
    }

    private func deleteHistory() async {
        if await viewModel.deleteHistory() {
            confirmingHistoryDeletion = false
        }
    }
}

// MARK: - History card

/// One saved session: its date and outcome, then the therapist's plan against what was done.
struct TMFingerHistoryCard: View {
    let summary: FingerSessionSummary

    var body: some View {
        TMTherapyCard(color: TherapyPalette.canvas, outlined: true, padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(summary.started, format: .dateTime.weekday(.wide).day().month(.abbreviated).year())
                        .typography(size: 24, weight: .semiBold, relativeTo: .headline)
                    Spacer(minLength: 12)
                    Label(outcomeTitle, systemImage: outcomeSymbol)
                        .typography(size: 20, weight: .medium, relativeTo: .subheadline)
                }
                ForEach(summary.routine.exercises) { exercise in
                    resultRow(exercise, result: summary.results.first { $0.kind == exercise })
                }

                Divider()
                HStack(alignment: .top, spacing: 24) {
                    Text(summary.feeling == .painful ? "progress.painRecorded" : "progress.painUnrecorded")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("progress.assistanceUnrecorded")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .typography(.subheadline)
                .foregroundStyle(TherapyPalette.muted)

            }
            .foregroundStyle(TherapyPalette.ink)
            .multilineTextAlignment(.leading)
        }
    }

    private var outcomeSymbol: String {
        if summary.outcome == .completed { return "checkmark" }
        return summary.totalRepetitions > 0 ? "checkmark.square" : "minus.square"
    }

    private var outcomeTitle: LocalizedStringKey {
        if summary.outcome == .completed { return "progress.outcome.completed" }
        return summary.totalRepetitions > 0 ? "progress.partial" : "progress.notDone"
    }

    private func resultRow(_ exercise: FingerExercise, result: FingerExerciseResult?) -> some View {
        let performed = (result?.repetitions ?? 0) > 0 || (result?.activeSeconds ?? 0) > 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "hand.raised").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(exercise.title))
                        .typography(size: 22, weight: .semiBold, relativeTo: .headline)
                    if let result, performed {
                        Text("progress.duration \(PracticeReport.minutes(result.activeSeconds))")
                            .typography(.subheadline)
                            .foregroundStyle(TherapyPalette.muted)
                    } else {
                        Text("progress.notDone").typography(.subheadline).foregroundStyle(TherapyPalette.muted)
                    }
                }
            }

            HStack(alignment: .top, spacing: 24) {
                column(title: "progress.plan", value: plan)
                column(
                    title: performed ? "progress.done" : "progress.actual",
                    value: result.flatMap { performed ? done($0) : nil } ?? Text("progress.notDone")
                )
            }
        }
    }

    private func column(title: LocalizedStringKey, value: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .typography(size: 18, weight: .regular, relativeTo: .subheadline)
                .foregroundStyle(TherapyPalette.muted)
            value
                .typography(size: 22, weight: .regular, relativeTo: .body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var plan: Text {
        Text("progress.planValue \(summary.routine.sets) \(summary.routine.repetitions)")
    }

    private func done(_ result: FingerExerciseResult) -> Text {
        let repetitions = summary.routine.repetitions
        let fullSets = result.completedSets > 0 && result.repetitions == result.completedSets * repetitions

        guard fullSets else {
            return Text("progress.doneRepetitions \(result.repetitions)")
        }

        return Text("progress.doneValue \(result.completedSets) \(repetitions) \(result.repetitions)")
    }
}

struct TMFingerReportDetailView<ViewModel: FingerReportDetailViewModelProtocol>: View {
    @State private var viewModel: ViewModel

    init(viewModel: ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            if let summary = viewModel.summary {
                report(summary).padding(32)
            } else {
                Text("reports.loading").typography(.title).padding(40)
            }
        }
        .foregroundStyle(TherapyPalette.ink).background(TherapyPalette.cream)
        .navigationTitle("report.titleShort")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private func report(_ summary: FingerSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                TMTherapyStatus(title: "report.tag", symbol: "sparkles")
                Spacer()
                Text(summary.started, format: .dateTime.day().month(.wide).year()).typography(.body)
            }
            Text("report.title").typography(.largeTitle)
            Text("report.encouragement").typography(.body).foregroundStyle(TherapyPalette.muted)
            if summary.feeling == .painful {
                TMTherapyError(key: "report.painNote")
            }
            TMTherapyCard(color: TherapyPalette.green) {
                HStack {
                    TMTherapyMetric(title: "report.duration", value: duration(summary.duration), light: true)
                    TMTherapyMetric(title: "report.sets", value: String(summary.totalSets), light: true)
                    TMTherapyMetric(title: "report.repetitions", value: String(summary.totalRepetitions), light: true)
                    TMTherapyMetric(title: "plan.side", value: String(localized: String.LocalizationValue(summary.routine.side.title), bundle: AppLanguage.selected.resourceBundle), light: true)
                }
            }
            HStack {
                Text(LocalizedStringKey("outcome." + summary.outcome.rawValue)).typography(.headline)
                Spacer()
                if let feeling = summary.feeling {
                    Label(LocalizedStringKey(feeling.title), systemImage: feeling.symbol).typography(.headline)
                }
            }
            Text("report.movement").typography(.title2)
            ForEach(summary.results) { result in
                TMTherapyCard {
                    HStack(spacing: 20) {
                        Image(systemName: result.kind.symbol).typography(size: 34, weight: .bold)
                            .foregroundStyle(TherapyPalette.green).frame(width: 50)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(result.kind.title)).typography(.headline)
                            Text(resultStatus(result)).typography(.footnote)
                        }
                        Spacer()
                        TMTherapyMetric(title: "report.sets", value: String(result.completedSets)).frame(width: 110)
                        TMTherapyMetric(title: "session.repetitions", value: String(result.repetitions)).frame(width: 130)
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("report.cameraIndex").typography(.footnote)
                            if let gain = result.observedGain, gain > 0.05 {
                                Text(verbatim: String(format: "+%.0f%%", gain * 100)).typography(.title2).foregroundStyle(TherapyPalette.green)
                            } else {
                                Text("report.noChange").typography(.body)
                            }
                        }.frame(width: 210)
                    }
                }
            }
            replaySection(summary)
            Text("report.cameraNoteShort").typography(.footnote).foregroundStyle(TherapyPalette.muted)
            DisclosureGroup("report.measurementDetails") {
                Text("report.measurementNote").typography(.body)
                    .foregroundStyle(TherapyPalette.muted).padding(.top, 12)
            }
            .typography(.body).tint(TherapyPalette.green)
            TMTherapyButton(title: "report.delete", symbol: "trash", secondary: true) {
                Task {
                    await viewModel.delete(summary)
                }
            }
        }
    }

    // MARK: - Key repetitions

    /// The first, hardest and last repetition of every recorded set, as a hand replay or clip.
    @ViewBuilder
    private func replaySection(_ summary: FingerSessionSummary) -> some View {
        if viewModel.replaysLoaded {
            let recorded = summary.results.filter { !viewModel.replaySets(for: $0.kind).isEmpty }

            if !recorded.isEmpty {
                Text("report.keyReps").typography(.title2)

                ForEach(recorded) { result in
                    ForEach(viewModel.replaySets(for: result.kind), id: \.setNumber) { set in
                        replayCard(set)
                    }
                }
            }

            if viewModel.replaysUnavailable {
                Text("history.report.replaysUnavailable")
                    .typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
            }
        }
    }

    private func replayCard(_ set: FingerKeyReps) -> some View {
        TMTherapyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: set.exercise.symbol)
                        .foregroundStyle(TherapyPalette.green)
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(set.exercise.title))
                        .typography(.headline)
                    Spacer()
                    Text("report.setNumber \(set.setNumber)")
                        .typography(.body)
                        .foregroundStyle(TherapyPalette.muted)
                }

                TMKeyRepReplaySection(
                    reps: viewModel.reps(in: set),
                    emphasizedJoints: { _ in HandSkeleton.emphasis(for: set.exercise) },
                    clipURL: { viewModel.clipURL(for: $0, in: set) },
                    isTrackingLow: viewModel.isTrackingLow
                )
            }
        }
    }

    private func resultStatus(_ result: FingerExerciseResult) -> LocalizedStringKey {
        if result.skipped {
            return "report.skipped"
        }
        if result.completed {
            return "report.completed"
        }
        return "report.partial"
    }

    private func duration(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockReportsViewModel: ReportsViewModelProtocol {
    var path: [HistoryRoute] = []
    let fingerHistory: [FingerSessionSummary] = [
        FingerSessionSummary(
            id: UUID(),
            started: .now,
            ended: .now,
            routine: FingerRoutine(),
            results: [],
            outcome: .completed,
            feeling: nil,
            exerciseIndex: 0
        )
    ]
    let armHistory: [SessionSummary] = []
    let errorKey: String? = nil
    let deletingHistory = false

    func refresh() async {}

    func deleteHistory() async -> Bool {
        true
    }
}

@MainActor
@Observable
private final class MockCellViewModel: HistoryCellViewModelProtocol {
    let entry: HistoryEntry

    init(entry: HistoryEntry) {
        self.entry = entry
    }

    func onTap() {}
}

@MainActor
private struct MockHistoryBuilder: HistoryContentBuildable {
    @ViewBuilder func buildCell(entry: HistoryEntry) -> some View {
        TMHistoryCellView(viewModel: MockCellViewModel(entry: entry))
    }

    @ViewBuilder func buildFingerReport(id: UUID) -> some View {
        Text(verbatim: "Finger report")
    }

    @ViewBuilder func buildSessionReport(id: UUID) -> some View {
        Text(verbatim: "Session report")
    }
}

@MainActor
@Observable
private final class MockFingerReportDetailViewModel: FingerReportDetailViewModelProtocol {
    let summary: FingerSessionSummary? = FingerSessionSummary(
        id: UUID(),
        started: .now,
        ended: .now,
        routine: FingerRoutine(),
        results: [],
        outcome: .completed,
        feeling: nil,
        exerciseIndex: 0
    )
    let replaysLoaded = true
    let replaysUnavailable = false

    func load() async {}
    func delete(_ summary: FingerSessionSummary) async {}

    func replaySets(for exercise: FingerExercise) -> [FingerKeyReps] {
        []
    }

    func reps(in set: FingerKeyReps) -> [KeyRep] {
        []
    }

    func clipURL(for rep: KeyRep, in set: FingerKeyReps) -> URL? {
        nil
    }

    func isTrackingLow(_ rep: KeyRep) -> Bool {
        false
    }
}

#Preview("Reports") {
    TMFingerReportsView(viewModel: MockReportsViewModel(), builder: MockHistoryBuilder())
}

#Preview("Finger report") {
    NavigationStack {
        TMFingerReportDetailView(viewModel: MockFingerReportDetailViewModel())
    }
}
#endif
