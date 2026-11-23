//
//  HomeView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 29/10/2026.
//

import SwiftUI

/// Beranda is one page whose reusable header, calendar, plan rows and floating action change
/// with the selected date. It owns the Home tab's stack, settings sheet and plan cover.
struct TMHomeView<ViewModel: HomeViewModelProtocol, Builder: HomeContentBuildable>: View {
    @State private var viewModel: ViewModel
    private let builder: Builder

    @Environment(\.buttonFeedback) private var buttonFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ViewModel, builder: Builder) {
        _viewModel = State(initialValue: viewModel)
        self.builder = builder
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            content
                .navigationDestination(for: HomeRoute.self) { route in
                    destination(route)
                }
        }
        .sheet(item: $viewModel.sheet) { sheet in
            NavigationStack {
                sheetContent(sheet)
            }
            .modalEnvironment(buttonFeedback: buttonFeedback)
        }
        .fullScreenCover(item: $viewModel.cover) { cover in
            TMPlanCoverHost(route: cover.route, builder: builder)
                .modalEnvironment(buttonFeedback: buttonFeedback)
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func destination(_ route: HomeRoute) -> some View {
        switch route {
        case .planIntro(let itemID):
            builder.buildDailyPlanIntro(
                itemID: itemID,
                countdownSeconds: nil,
                automatic: false
            )
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .practicePreferences:
            builder.buildPracticePreferences()
        }
    }

    // MARK: - Page

    private var content: some View {
        VStack(spacing: 0) {
            header

            calendar
                .padding(.top, 21)

            dayContent
                .padding(.top, 21)
        }
        .frame(maxWidth: 1142)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 26)
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas)
        .overlay(alignment: .bottom) {
            floatingAction
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                TMDebugActionButton(title: "debug.trySitToStand", symbol: "figure.stand") {
                    viewModel.begin(from: BalanceExercise.sitToStand.rawValue)
                }
                .disabled(!viewModel.rows.contains { $0.id == BalanceExercise.sitToStand.rawValue })
            }

            ToolbarItem(placement: .topBarLeading) {
                debugStartMenu
            }
            #endif

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.openPracticePreferences()
                } label: {
                    Label("cognitive.settings", systemImage: "gearshape")
                }
            }
        }
        .task {
            await viewModel.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.synchronizeCalendarDay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            viewModel.synchronizeCalendarDay()
        }
    }

    #if DEBUG
    /// Debug builds only: opens any shown plan exercise's normal intro, whatever the earlier
    /// items' state, through the same `begin(from:)` a tapped card uses. Hidden exercises are
    /// not in `rows`, so they cannot be chosen.
    private var debugStartMenu: some View {
        TMDebugMenu(title: "debug.startAnyExercise", symbol: "list.number") {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    viewModel.begin(from: row.id)
                } label: {
                    Label {
                        Text(verbatim: "\(index + 1). ") + Text(LocalizedStringKey(row.titleKey))
                    } icon: {
                        Image(systemName: row.status == .done ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        }
        .disabled(viewModel.rows.isEmpty)
    }
    #endif

    private var header: some View {
        VStack(spacing: 8) {
            TMHomeHeaderTitle(text: dateTitle)
            TMHomeHeaderSubtitle(text: headerSubtitle)
        }
        .frame(maxWidth: 1010, minHeight: 90, alignment: .top)
    }

    private var calendar: some View {
        TMDailyPlanCalendar(
            dates: viewModel.visibleWeek,
            selectedDate: viewModel.selectedDate
        ) { date in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.selectDate(date)
            }
        } onMoveWeek: { offset in
            viewModel.moveVisibleWeek(by: offset)
        }
    }

    @ViewBuilder
    private var dayContent: some View {
        switch viewModel.selectedDayState {
        case .noSchedule:
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .completed, .missed, .partial, .current, .upcoming:
            planList
        }
    }

    private var planList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let rows = displayedRows

                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]

                    TMDailyPlanCard(
                        title: LocalizedStringKey(row.titleKey),
                        sets: sets(in: row),
                        repetitions: repetitions(in: row),
                        duration: estimatedDuration(at: index),
                        state: cardState(for: row, index: index),
                        isLast: index == rows.index(before: rows.endIndex)
                    ) {
                        startPlan(from: row.id)
                    }
                }
            }
            .frame(maxWidth: 1041)
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.bottom, viewModel.selectedDayState == .completed ? 48 : 188)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            TMHomeHeaderTitle(text: Text("home.dailyPlan.emptyTitle"))
            TMHomeHeaderSubtitle(
                text: Text("home.dailyPlan.emptySubtitle"),
                color: TherapyPalette.planMutedInk
            )
        }
        .padding(.bottom, 120)
    }

    // MARK: - Presentation

    private var dateTitle: Text {
        Text(
            viewModel.selectedDate,
            format: .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .year()
        )
    }

    private var headerSubtitle: Text {
        switch viewModel.selectedDayState {
        case .completed:
            return Text("home.dailyPlan.completed")
        case .missed:
            return Text("home.dailyPlan.missed")
        case .partial:
            return Text("home.dailyPlan.partial")
        case .current:
            return Text("home.dailyPlan.progress \(viewModel.completedCount) \(viewModel.rows.count)")
        case .upcoming:
            return Text("home.dailyPlan.upcoming")
        case .noSchedule:
            return Text("home.dailyPlan.noSchedule")
        }
    }

    private var displayedRows: [DailyPlanRow] {
        viewModel.rows
    }

    private func cardState(for row: DailyPlanRow, index: Int) -> TMDailyPlanCardState {
        switch viewModel.selectedDayState {
        case .completed:
            return .completed
        case .partial:
            return viewModel.selectedCompletedItemIDs.contains(row.id)
                ? .completed
                : .upcoming(step: index + 1)
        case .missed, .upcoming, .noSchedule:
            return .upcoming(step: index + 1)
        case .current:
            switch row.status {
            case .done:
                return .completed
            case .next:
                return .current(step: index + 1)
            case .upcoming:
                return .upcoming(step: index + 1)
            }
        }
    }

    private func sets(in row: DailyPlanRow) -> Int {
        for detail in row.details {
            if case .sets(let count) = detail {
                return count
            }
        }

        return 1
    }

    private func repetitions(in row: DailyPlanRow) -> Int {
        for detail in row.details {
            if case .repetitions(let count) = detail {
                return count
            }
        }

        return 1
    }

    private func estimatedDuration(at index: Int) -> ClosedRange<Int> {
        if viewModel.selectedDayState == .current, index < 2 {
            return 10...15
        }

        return 4...6
    }

    // MARK: - Actions

    @ViewBuilder
    private var floatingAction: some View {
        switch viewModel.selectedDayState {
        case .completed:
            if isViewingPastDate {
                returnToTodayButton
            }

        case .missed:
            returnToTodayButton

        case .partial:
            returnToTodayButton

        case .current:
            TMHomeFloatingButton(
                title: viewModel.hasProgress ? "plan.continue" : "home.startExercise",
                symbol: "play.fill",
                style: .prominent
            ) {
                startPlan(from: nil)
            }

        case .upcoming:
            TMHomeFloatingButton(
                title: "home.startExercise",
                symbol: "lock.fill",
                style: .disabled,
                action: {}
            )

        case .noSchedule:
            returnToTodayButton
        }
    }

    private var isViewingPastDate: Bool {
        let calendar = Calendar.autoupdatingCurrent
        let selectedDate = calendar.startOfDay(for: viewModel.selectedDate)
        let today = calendar.startOfDay(for: .now)

        return selectedDate < today
    }

    private var returnToTodayButton: some View {
        TMHomeFloatingButton(
            title: "home.dailyPlan.returnToday",
            symbol: "arrow.uturn.backward",
            style: .outlined
        ) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.returnToToday()
            }
        }
    }

    private func startPlan(from itemID: String?) {
        guard viewModel.selectedDayState == .current else {
            return
        }

        viewModel.begin(from: itemID)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockHomeViewModel: HomeViewModelProtocol {
    var path: [HomeRoute] = []
    var sheet: HomeSheet?
    var cover: PlanCover?
    let rows: [DailyPlanRow]
    let errorKey: String? = nil
    let isFinishedToday: Bool
    let completedCount: Int
    let hasProgress: Bool
    let selectedDayState: HomeDayState
    let selectedCompletedItemIDs: Set<String>
    var selectedDate: Date
    var visibleWeek: [Date]

    init(state: HomeDayState) {
        selectedDayState = state
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) ?? today
        visibleWeek = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        selectedDate = today

        let items = Array(DailyPlan.standard.prefix(4))
        rows = items.enumerated().map { index, item in
            DailyPlanRow(
                item: item,
                titleKey: DailyPlanViewModel.titleKey(for: item.exercise),
                details: [.sets(3), .repetitions(8)],
                status: index == 0 ? .done : (index == 1 ? .next : .upcoming)
            )
        }
        selectedCompletedItemIDs = state == .partial ? [rows[0].id] : []
        isFinishedToday = state == .completed
        completedCount = state == .completed ? rows.count : 1
        hasProgress = completedCount > 0
    }

    func refresh() async {}
    func openPracticePreferences() {}
    func selectDate(_ date: Date) { selectedDate = date }
    func moveVisibleWeek(by offset: Int) {
        visibleWeek = visibleWeek.compactMap {
            Calendar.autoupdatingCurrent.date(byAdding: .day, value: offset * 7, to: $0)
        }
    }
    func synchronizeCalendarDay() {}
    func returnToToday() { selectedDate = .now }
    func begin(from itemID: String?) {}
}

@MainActor
private struct MockHomeBuilder: HomeContentBuildable {
    @ViewBuilder func buildCoverPage(_ route: PlanCoverRoute) -> some View {
        Text(verbatim: "Plan cover")
    }

    @ViewBuilder func buildDailyPlanIntro(
        itemID: String,
        countdownSeconds: Int?,
        automatic: Bool
    ) -> some View {
        Text(verbatim: "Intro \(itemID)")
    }

    @ViewBuilder func buildPracticePreferences() -> some View {
        Text(verbatim: "Settings")
    }
}

#Preview("Beranda — Selesai") {
    TMHomeView(viewModel: MockHomeViewModel(state: .completed), builder: MockHomeBuilder())
}

#Preview("Beranda — Hari Ini") {
    TMHomeView(viewModel: MockHomeViewModel(state: .current), builder: MockHomeBuilder())
}

#Preview("Beranda — Tidak Latihan") {
    TMHomeView(viewModel: MockHomeViewModel(state: .missed), builder: MockHomeBuilder())
}

#Preview("Beranda — Sebagian Selesai") {
    TMHomeView(viewModel: MockHomeViewModel(state: .partial), builder: MockHomeBuilder())
}

#Preview("Beranda — Besok") {
    TMHomeView(viewModel: MockHomeViewModel(state: .upcoming), builder: MockHomeBuilder())
}

#Preview("Beranda — Tanpa Jadwal") {
    TMHomeView(viewModel: MockHomeViewModel(state: .noSchedule), builder: MockHomeBuilder())
}
#endif
