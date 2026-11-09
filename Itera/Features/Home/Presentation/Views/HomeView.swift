//
//  HomeView.swift
//  Itera
//
//  Created by dimaswisodewo on 29/10/2026.
//

import SwiftUI

/// Beranda: a greeting, the button that starts today's plan, the plan as a timeline, and
/// every program below it. Once the start button scrolls away, it floats at the bottom.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(PermissionManager.self) private var permissions
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PracticePreferences.patientName) private var patientName = ""

    /// Permission and listening check run by an explicit Start, created once per screen.
    @State private var readiness: HomeViewModel?
    /// True once the inline start button has scrolled under the top edge.
    @State private var startButtonHidden = false
    @State private var starting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 56) {
                header
                timeline
                allPrograms
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
                    router.presentSheet(.practicePreferences)
                } label: {
                    Label("cognitive.settings", systemImage: "gearshape")
                }
            }
        }
        .task {
            await refresh()
        }
    }

    private static let scrollSpace = "home.scroll"

    private func refresh() async {
        if readiness == nil {
            readiness = HomeViewModel(
                permissions: permissions,
                audio: dependencies.audio,
                history: dependencies
            )
        }

        readiness?.refresh()
        await dependencies.home.refresh()
        await dependencies.routine.load()
        await dependencies.taskRoutine.load()
        await dependencies.dailyPlan.load()
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
        if let readiness, !readiness.ready, readiness.message != "home.setup" {
            Text(LocalizedStringKey(readiness.message))
                .typography(.footnote)
                .foregroundStyle(TherapyPalette.muted)
        }

        if let error = dependencies.dailyPlan.errorKey {
            TherapyError(key: error)
        }

        if let error = dependencies.home.errorKey {
            TherapyError(key: error)
            TherapyButton(title: "action.retry", secondary: true) {
                Task { await dependencies.home.refresh() }
            }
            .frame(maxWidth: 360)
        }
    }

    // MARK: - Start

    private var startButton: some View {
        TherapyButton(
            title: startTitle,
            symbol: dependencies.dailyPlan.isFinishedToday ? "checkmark" : "play.fill",
            disabled: starting,
            prominent: true
        ) {
            startPlan(from: nil)
        }
    }

    private var startTitle: LocalizedStringKey {
        let plan = dependencies.dailyPlan

        if plan.isFinishedToday {
            return "plan.doneToday"
        }

        if plan.completedCount > 0 || dependencies.home.checkpoint != nil {
            return "plan.continue"
        }

        return "home.startExercise"
    }

    @ViewBuilder
    private var floatingStart: some View {
        if startButtonHidden {
            TherapyFloatingActionDock {
                startButton
            }
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func startPlan(from itemID: String?) {
        guard let readiness, !starting else {
            return
        }

        starting = true
        Task {
            await dependencies.dailyPlan.start(
                from: itemID,
                readiness: readiness,
                dependencies: dependencies,
                router: router
            )
            starting = false
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        let rows = dependencies.dailyPlan.rows(in: dependencies)

        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]

                TherapyTimelineRow(
                    state: Self.timelineState(row.status),
                    isFirst: index == rows.startIndex,
                    isLast: index == rows.index(before: rows.endIndex)
                ) {
                    TherapyPlanCard(
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

    // MARK: - All programs

    private var allPrograms: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("home.allPrograms")
                .typography(size: 28, weight: .semiBold, relativeTo: .title2)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: programColumns, alignment: .leading, spacing: 24) {
                TherapyProgramCard(
                    title: "home.program.finger",
                    detail: "home.setsReps \(dependencies.home.routine.sets) \(dependencies.home.routine.repetitions)",
                    artwork: "hand-hero",
                    mirrored: dependencies.home.routine.side == .left
                ) {
                    router.push(.fingerHome(.fingers))
                }
                TherapyProgramCard(
                    title: "home.armPractice",
                    detail: "home.program.armDetail",
                    artwork: "symbol:figure.arms.open"
                ) {
                    router.push(.therapyOverview(.arm))
                }
                TherapyProgramCard(
                    title: "balance.title",
                    detail: "home.program.balanceDetail",
                    artwork: "symbol:figure.stand"
                ) {
                    router.push(.balanceOverview(.crossMidline))
                }
                TherapyProgramCard(
                    title: "exercise.forearmRotation",
                    detail: "home.viewShort",
                    artwork: "hand-forearmRotation",
                    mirrored: dependencies.homeModel(for: .forearm).routine.side == .left
                ) {
                    router.push(.fingerHome(.forearm))
                }
                TherapyProgramCard(title: "home.trunkPractice", detail: "home.viewShort", artwork: "symbol:figure.seated.side") {
                    router.push(.balanceOverview(.sitToStand))
                }
                TherapyProgramCard(title: "rotation.category", detail: "home.viewShort", artwork: "symbol:arrow.triangle.2.circlepath") {
                    router.push(.armRotationHome)
                }
                TherapyProgramCard(title: "task.category", detail: "home.viewShort", artwork: "symbol:square.stack.3d.up") {
                    router.push(.therapyOverview(.taskOriented))
                }
            }
        }
    }

    private var programColumns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: count)
    }
}
