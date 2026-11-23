//
//  HomeView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 29/10/2026.
//

import SwiftUI

/// Beranda is one page whose reusable header, calendar, plan rows and floating action change
/// with the selected date. It owns the Home tab's stack, Preferences panel and plan cover.
struct TMHomeView<ViewModel: HomeViewModelProtocol, Builder: HomeContentBuildable>: View {
    @State private var viewModel: ViewModel
    private let builder: Builder

    #if DEBUG
    /// Presentation-only override for reviewing Beranda states without changing saved progress.
    @State private var debugDayStateOverride: HomeDayState?
    #endif

    @Environment(\.buttonFeedback) private var buttonFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ViewModel, builder: Builder) {
        _viewModel = State(initialValue: viewModel)
        self.builder = builder

        #if DEBUG
        _debugDayStateOverride = State(initialValue: nil)
        #endif
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            content
                .navigationDestination(for: HomeRoute.self) { route in
                    destination(route)
                }
        }
        // Preferences floats over the whole stack on a frosted backdrop, like History's
        // exercise detail. A system sheet cannot frost what lies behind it.
        .overlay {
            panel
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.panel)
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
    private var panel: some View {
        if let panel = viewModel.panel {
            TMDetailPanel(
                closeTitle: "action.close",
                maxWidth: 720,
                scrollsContent: false,
                showsCloseButton: false
            ) {
                viewModel.panel = nil
            } content: {
                NavigationStack {
                    panelContent(panel)
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func panelContent(_ panel: HomePanel) -> some View {
        switch panel {
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
    /// Debug builds only: opens any shown plan exercise's normal intro or previews Beranda's
    /// date states without changing the saved daily-plan progress.
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

            Divider()

            Section {
                debugDayStateButton(.missed, title: ".missed")
                debugDayStateButton(.current, title: ".current")
                debugDayStateButton(.partial, title: ".partial")
                debugDayStateButton(.completed, title: ".completed")
            } header: {
                Text(verbatim: "Preview state Beranda")
            }

            Divider()

            Button {
                clearDebugDayState()
            } label: {
                Label {
                    Text(verbatim: "Gunakan data asli")
                } icon: {
                    Image(
                        systemName: debugDayStateOverride == nil
                            ? "checkmark"
                            : "arrow.counterclockwise"
                    )
                }
            }
        }
        .disabled(viewModel.rows.isEmpty)
    }

    private func debugDayStateButton(
        _ state: HomeDayState,
        title: String
    ) -> some View {
        Button {
            setDebugDayState(state)
        } label: {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: debugDayStateOverride == state ? "checkmark" : "circle")
            }
        }
    }

    private func setDebugDayState(_ state: HomeDayState?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            debugDayStateOverride = state

            guard let state else {
                viewModel.returnToToday()
                return
            }

            switch state {
            case .current:
                viewModel.returnToToday()
            case .missed, .partial, .completed:
                selectYesterdayForDebugPreview()
            case .upcoming, .noSchedule:
                break
            }
        }
    }

    private func clearDebugDayState() {
        setDebugDayState(nil)
    }

    private func selectYesterdayForDebugPreview() {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return
        }

        viewModel.selectDate(yesterday)
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
        switch presentedDayState {
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
                        isLast: index == rows.index(before: rows.endIndex),
                        isInteractionEnabled: canInteractWithCards
                    ) {
                        startPlan(from: row.id)
                    }
                }
            }
            .frame(maxWidth: 1041)
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.bottom, presentedDayState == .completed ? 48 : 188)
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
        switch presentedDayState {
        case .completed:
            return Text("home.dailyPlan.completed")
        case .missed:
            return Text("home.dailyPlan.missed")
        case .partial:
            return Text("home.dailyPlan.partial")
        case .current:
            return Text("home.dailyPlan.progress \(presentedCompletedCount) \(viewModel.rows.count)")
        case .upcoming:
            return Text("home.dailyPlan.upcoming")
        case .noSchedule:
            return Text("home.dailyPlan.noSchedule")
        }
    }

    private var displayedRows: [DailyPlanRow] {
        viewModel.rows
    }

    private var presentedDayState: HomeDayState {
        #if DEBUG
        if let debugDayStateOverride {
            return debugDayStateOverride
        }
        #endif

        return viewModel.selectedDayState
    }

    private var presentedCompletedCount: Int {
        #if DEBUG
        if let debugDayStateOverride {
            switch debugDayStateOverride {
            case .missed, .upcoming, .noSchedule:
                return 0
            case .current, .partial:
                return min(1, viewModel.rows.count)
            case .completed:
                return viewModel.rows.count
            }
        }
        #endif

        return viewModel.completedCount
    }

    private var presentedHasProgress: Bool {
        #if DEBUG
        if debugDayStateOverride != nil {
            return presentedCompletedCount > 0
        }
        #endif

        return viewModel.hasProgress
    }

    private var canInteractWithCards: Bool {
        switch presentedDayState {
        case .current:
            return true
        case .completed, .missed, .partial, .upcoming, .noSchedule:
            return false
        }
    }

    private func cardState(for row: DailyPlanRow, index: Int) -> TMDailyPlanCardState {
        #if DEBUG
        if let debugDayStateOverride {
            return debugCardState(for: debugDayStateOverride, index: index)
        }
        #endif

        switch presentedDayState {
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

    #if DEBUG
    private func debugCardState(
        for state: HomeDayState,
        index: Int
    ) -> TMDailyPlanCardState {
        switch state {
        case .completed:
            return .completed
        case .partial:
            return index == 0 ? .completed : .upcoming(step: index + 1)
        case .missed, .upcoming, .noSchedule:
            return .upcoming(step: index + 1)
        case .current:
            if viewModel.rows.count == 1 {
                return .current(step: 1)
            }

            if index == 0 {
                return .completed
            }

            if index == 1 {
                return .current(step: index + 1)
            }

            return .upcoming(step: index + 1)
        }
    }
    #endif

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
        if presentedDayState == .current, index < 2 {
            return 10...15
        }

        return 4...6
    }

    // MARK: - Actions

    @ViewBuilder
    private var floatingAction: some View {
        switch presentedDayState {
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
                title: presentedHasProgress ? "plan.continue" : "home.startExercise",
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
                #if DEBUG
                debugDayStateOverride = nil
                #endif

                viewModel.returnToToday()
            }
        }
    }

    private func startPlan(from itemID: String?) {
        guard presentedDayState == .current else {
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
    var panel: HomePanel?
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
