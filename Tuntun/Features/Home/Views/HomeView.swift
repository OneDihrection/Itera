//
//  HomeView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 29/10/2026.
//

import SwiftUI

/// Beranda shows today's plan as a timeline. The start button floats at the bottom
/// once the inline button scrolls away. It owns the Home tab's stack, its settings sheet and
/// the full-screen cover that runs today's plan.
struct TMHomeView<ViewModel: HomeViewModelProtocol, Builder: HomeContentBuildable>: View {
    @State private var viewModel: ViewModel
    private let builder: Builder
    @Environment(\.buttonFeedback) private var buttonFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PracticePreferences.patientName) private var patientName = ""

    /// True once the inline start button has scrolled under the top edge.
    @State private var startButtonHidden = false

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

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 56) {
                header
                timeline
            }
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
            .scenePadding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 180)
        }
        .coordinateSpace(name: Self.scrollSpace)
        .overlay(alignment: .bottom) {
            floatingStart
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.openPracticePreferences()
                } label: {
                    Label("cognitive.settings", systemImage: "gearshape")
                }
            }
        }
        .task {
            await refresh()
        }
    }

    private static var scrollSpace: String { "home.scroll" }

    private func refresh() async {
        await viewModel.refresh()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            greetingTitle
                .typography(size: 44, weight: .bold, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)

            Text("home.wellWishes")
                .typography(size: 26, weight: .regular, relativeTo: .title3)

            startButton
                .padding(.top, 24)
                .onGeometryChange(for: Bool.self) { proxy in
                    proxy.frame(in: .named(Self.scrollSpace)).maxY < 0
                } action: { hidden in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        startButtonHidden = hidden
                    }
                }

            statusMessages
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// "Halo, Bu Yuli!" when a name is set in Settings, otherwise "Halo!".
    private var greetingTitle: Text {
        let name = patientName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return Text("home.hello")
        }

        return Text("home.greetingName \(name)")
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let error = viewModel.errorKey {
            TMTherapyError(key: error)
        }

    }

    // MARK: - Start

    private var startButton: some View {
        TMTherapyButton(
            title: startTitle,
            symbol: viewModel.isFinishedToday ? "checkmark" : "play.fill",
            prominent: true
        ) {
            startPlan(from: nil)
        }
    }

    private var startTitle: LocalizedStringKey {
        if viewModel.isFinishedToday {
            return "plan.doneToday"
        }

        if viewModel.hasProgress {
            return "plan.continue"
        }

        return "home.startExercise"
    }

    @ViewBuilder
    private var floatingStart: some View {
        if startButtonHidden {
            TMTherapyFloatingActionDock {
                startButton
            }
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Opens the intro of the next exercise (or the tapped one); the intro's own Start is the
    /// explicit start that validates permissions and listening.
    private func startPlan(from itemID: String?) {
        viewModel.begin(from: itemID)
    }

    // MARK: - Timeline

    private var timeline: some View {
        let rows = viewModel.rows

        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]

                TMTherapyTimelineRow(
                    state: Self.timelineState(row.status),
                    previousIsDone: index > rows.startIndex && rows[index - 1].status == .done,
                    isFirst: index == rows.startIndex,
                    isLast: index == rows.index(before: rows.endIndex)
                ) {
                    TMTherapyPlanCard(
                        title: LocalizedStringKey(row.titleKey),
                        details: row.details.map(Self.planDetail),
                        artwork: row.item.artwork,
                        fallbackArtwork: row.item.fallbackArtwork,
                        state: Self.timelineState(row.status)
                    ) {
                        startPlan(from: row.id)
                    }
                }
            }
        }
    }

    private static func timelineState(_ status: DailyPlanRow.Status) -> TherapyTimelineState {
        switch status {
        case .done:
            return .done
        case .next:
            return .current
        case .upcoming:
            return .upcoming
        }
    }

    static func planDetail(_ detail: DailyPlanRow.Detail) -> TherapyPlanDetail {
        switch detail {
        case .sets(let count):
            return TherapyPlanDetail(symbol: "rectangle.stack", text: "plan.sets \(count)")
        case .repetitions(let count):
            return TherapyPlanDetail(symbol: "arrow.triangle.2.circlepath", text: "plan.repetitions \(count)")
        case .holdSeconds(let seconds):
            return TherapyPlanDetail(symbol: "timer", text: "plan.holdSeconds \(seconds)")
        }
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
    let rows: [DailyPlanRow] = []
    let errorKey: String? = nil
    let isFinishedToday = false
    let hasProgress = false

    func refresh() async {}
    func openPracticePreferences() {}
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

#Preview("Beranda") {
    TMHomeView(viewModel: MockHomeViewModel(), builder: MockHomeBuilder())
}
#endif
