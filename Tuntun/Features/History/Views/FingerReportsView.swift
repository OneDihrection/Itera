//
//  FingerReportsView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

/// The Progress tab: this week's practice in `TMProgressHeaderCard` and every day's practice in
/// `TMMonthlyCalendar`, whose days open a day's progress page through the router. It owns the
/// tab's navigation stack.
struct TMFingerReportsView<ViewModel: ReportsViewModelProtocol, Builder: HistoryContentBuildable>: View {
    @State private var viewModel: ViewModel
    private let builder: Builder

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
        // Pages pushed from Progress are its children, so the Beranda/Progres tab bar hides
        // while any is open. It is set once, outside the stack, from the path: a modifier on
        // the pushed page itself flipped the bar during the pop transition and it flickered.
        .toolbar(viewModel.path.isEmpty ? .visible : .hidden, for: .tabBar)
        // The detail panel floats over the whole stack, navigation bar included, like a
        // detail card in the iPad App Store.
        .overlay {
            exerciseDetail
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.exerciseDetail)
    }

    @ViewBuilder
    private var exerciseDetail: some View {
        if let route = viewModel.exerciseDetail {
            TMDetailPanel(closeTitle: "action.close") {
                viewModel.dismissExerciseDetail()
            } content: {
                builder.buildExerciseDetail(route)
            }
            .id(route.id)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func destination(_ route: HistoryRoute) -> some View {
        switch route {
        case .fingerReport(let id):
            builder.buildFingerReport(id: id)
        case .sessionReport(let id):
            builder.buildSessionReport(id: id)
        case .practiceDay(let day):
            builder.buildPracticeDay(day)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                headerCard

                VStack(alignment: .leading, spacing: 16) {
                    Text("reports.history")
                        .typography(size: 30, weight: .semiBold, relativeTo: .title2)
                        .accessibilityAddTraits(.isHeader)

                    calendar
                }

                errorSection
            }
            .frame(maxWidth: 1040)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.progressCanvas)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Sections

    private var headerCard: some View {
        let count = viewModel.practiceHistory.practiceDayCount(inWeekOf: viewModel.today)
        let headline: LocalizedStringKey = count > 0
            ? "progress.header.headline \(count)"
            : "progress.header.empty"

        return TMProgressHeaderCard(
            caption: "progress.header.caption",
            headline: headline,
            badgeNumber: count
        )
    }

    private var calendar: some View {
        TMMonthlyCalendar(
            month: viewModel.displayedMonth,
            today: viewModel.today,
            statuses: viewModel.practiceHistory.statuses.mapValues(calendarStatus),
            canShowPreviousMonth: true,
            canShowNextMonth: viewModel.canShowNextMonth,
            onPreviousMonth: {
                viewModel.showPreviousMonth()
            },
            onNextMonth: {
                viewModel.showNextMonth()
            },
            onSelectDay: { day in
                viewModel.openDay(day)
            }
        )
    }

    private func calendarStatus(_ status: PracticeDayStatus) -> TMCalendarDayStatus {
        switch status {
        case .none:
            return .none
        case .partial:
            return .partial
        case .completed:
            return .completed
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.errorKey {
            VStack(alignment: .leading, spacing: 12) {
                TMTherapyError(key: error)

                TMTherapyButton(title: "action.retry", secondary: true, pill: true) {
                    Task { await viewModel.refresh() }
                }
            }
        }
    }
}

// MARK: - Finger report

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
    var exerciseDetail: ExerciseDetailRoute?
    let practiceHistory = PracticeHistory.preview
    private(set) var displayedMonth = Date.now
    let today = Date.now
    let errorKey: String? = nil

    var canShowNextMonth: Bool {
        !Calendar.current.isDate(displayedMonth, equalTo: today, toGranularity: .month)
    }

    func refresh() async {}

    func showPreviousMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    func showNextMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    func openDay(_ day: Date) {
        path.append(.practiceDay(day))
    }

    func dismissExerciseDetail() {
        exerciseDetail = nil
    }
}

@MainActor
private struct MockHistoryBuilder: HistoryContentBuildable {
    @ViewBuilder func buildFingerReport(id: UUID) -> some View {
        Text(verbatim: "Finger report")
    }

    @ViewBuilder func buildSessionReport(id: UUID) -> some View {
        Text(verbatim: "Session report")
    }

    @ViewBuilder func buildPracticeDay(_ day: Date) -> some View {
        Text(verbatim: "Practice day")
    }

    @ViewBuilder func buildExerciseDetail(_ route: ExerciseDetailRoute) -> some View {
        Text(verbatim: "Exercise detail")
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

#Preview("Progress") {
    TMFingerReportsView(viewModel: MockReportsViewModel(), builder: MockHistoryBuilder())
}

#Preview("Finger report") {
    NavigationStack {
        TMFingerReportDetailView(viewModel: MockFingerReportDetailViewModel())
    }
}
#endif
