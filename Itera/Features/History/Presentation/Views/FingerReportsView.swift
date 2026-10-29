//
//  FingerReportsView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerReportsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("reports.title").typography(.largeTitle)
                PracticeProgressSection()
                Text("reports.history").typography(.title)
                if let error = dependencies.home.errorKey {
                    TherapyError(key: error)
                    TherapyButton(title: "action.retry", secondary: true) { Task { await dependencies.home.refresh() } }
                }
                if dependencies.home.history.isEmpty {
                    TherapyCard(color: TherapyPalette.mint) {
                        VStack(alignment: .leading, spacing: 20) {
                            Image(systemName: "chart.bar.doc.horizontal").typography(size: 56, weight: .bold)
                            Text("reports.empty").typography(.title)
                            Text("reports.emptyDetail").typography(.body)
                            TherapyButton(title: "home.viewPlan", symbol: "play.fill") { router.push(.plan) }
                        }
                    }
                } else {
                    ForEach(dependencies.home.history) { summary in
                        Button { router.push(.report(summary.id)) } label: {
                            TherapyCard {
                                HStack(spacing: 24) {
                                    Image(systemName: summary.outcome == .completed ? "checkmark.seal.fill" : "clock.arrow.circlepath")
                                        .typography(size: 40, weight: .bold).foregroundStyle(TherapyPalette.green)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(summary.started, format: .dateTime.day().month(.wide).year()).typography(.title2)
                                        Text(LocalizedStringKey("outcome." + summary.outcome.rawValue)).typography(.footnote)
                                    }
                                    Spacer()
                                    TherapyMetric(title: "session.repetitions", value: String(summary.totalRepetitions)).frame(width: 150)
                                    Image(systemName: "arrow.up.right").typography(.title2)
                                }
                            }
                        }.buttonStyle(TherapySoundButtonStyle())
                    }
                }
            }.padding(32)
        }
        .foregroundStyle(TherapyPalette.ink).background(TherapyPalette.cream)
        .navigationTitle("tab.reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshProgress() }
    }

    private func refreshProgress() async {
        await dependencies.home.refresh()
        await dependencies.progress.refresh()
        if !dependencies.progress.pending.isEmpty {
            router.presentAchievementCelebration()
        }
    }
}

struct FingerReflectionView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @State private var selected: SessionFeeling?

    var body: some View {
        ScrollView {
            VStack(spacing: 38) {
                HStack {
                    Spacer()
                    Button { dependencies.session?.readReflection() } label: {
                        Image(systemName: "speaker.wave.2.fill").typography(.title2)
                            .foregroundStyle(TherapyPalette.onAccent)
                            .frame(width: 68, height: 68)
                            .background(TherapyPalette.primary, in: Circle())
                    }
                    .buttonStyle(TherapySoundButtonStyle()).accessibilityLabel("action.repeat")
                }
                Text("reflection.title").typography(.largeTitle).multilineTextAlignment(.center)
                HStack(spacing: 28) {
                    ForEach(Array(SessionFeeling.exerciseChoices.enumerated()), id: \.element.id) { index, feeling in
                        TherapyFeelingChoice(title: LocalizedStringKey(feeling.title),
                                             expression: index - 1, selected: selected == feeling) {
                            selected = feeling
                        }
                    }
                }
                .disabled(dependencies.session?.saving == true)
                TherapyButton(title: "action.next", disabled: selected == nil || dependencies.session?.saving == true) {
                    save()
                }.frame(maxWidth: 360)
                if dependencies.session?.saving == true {
                    ProgressView()
                }
                if let key = dependencies.session?.errorKey {
                    TherapyError(key: key)
                }
            }
            .padding(40).frame(maxWidth: 1150).frame(maxWidth: .infinity)
        }
        .foregroundStyle(TherapyPalette.ink)
        .frame(maxHeight: .infinity).background(TherapyPalette.cream)
        .interactiveDismissDisabled()
    }

    private func save() {
        guard let selected else {
            return
        }
        Task {
            if let summary = await dependencies.session?.recordFeeling(selected) {
                await dependencies.home.refresh()
                router.dismissFullScreenCover()
                router.push(.report(summary.id))
            }
        }
    }
}

struct FingerReportDetailView: View {
    let id: UUID
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    private var summary: FingerSessionSummary? {
        dependencies.home.history.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            if let summary {
                report(summary).padding(32)
            } else {
                Text("reports.loading").typography(.title).padding(40)
            }
        }
        .foregroundStyle(TherapyPalette.ink).background(TherapyPalette.cream)
        .navigationTitle("report.titleShort")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await dependencies.home.refresh()
            await dependencies.progress.refresh()
            if !dependencies.progress.pending.isEmpty {
                router.presentAchievementCelebration()
            }
        }
    }

    private func report(_ summary: FingerSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                TherapyStatus(title: "report.tag", symbol: "sparkles")
                Spacer()
                Text(summary.started, format: .dateTime.day().month(.wide).year()).typography(.body)
            }
            Text("report.title").typography(.largeTitle)
            Text("report.encouragement").typography(.body).foregroundStyle(TherapyPalette.muted)
            if summary.feeling == .painful {
                TherapyError(key: "report.painNote")
            }
            TherapyCard(color: TherapyPalette.green) {
                HStack {
                    TherapyMetric(title: "report.duration", value: duration(summary.duration), light: true)
                    TherapyMetric(title: "report.sets", value: String(summary.totalSets), light: true)
                    TherapyMetric(title: "report.repetitions", value: String(summary.totalRepetitions), light: true)
                    TherapyMetric(title: "plan.side", value: String(localized: String.LocalizationValue(summary.routine.side.title)), light: true)
                }
            }
            HStack {
                Text(LocalizedStringKey("outcome." + summary.outcome.rawValue)).typography(.headline)
                Spacer()
                if let feeling = summary.feeling {
                    Label(LocalizedStringKey(feeling.title), systemImage: feeling.symbol).typography(.headline)
                }
            }
            sessionAchievements(summary)
            Text("report.movement").typography(.title2)
            ForEach(summary.results) { result in
                TherapyCard {
                    HStack(spacing: 20) {
                        Image(systemName: result.kind.symbol).typography(size: 34, weight: .bold)
                            .foregroundStyle(TherapyPalette.green).frame(width: 50)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(result.kind.title)).typography(.headline)
                            Text(resultStatus(result)).typography(.footnote)
                        }
                        Spacer()
                        TherapyMetric(title: "report.sets", value: String(result.completedSets)).frame(width: 110)
                        TherapyMetric(title: "session.repetitions", value: String(result.repetitions)).frame(width: 130)
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
            Text("report.cameraNoteShort").typography(.footnote).foregroundStyle(TherapyPalette.muted)
            DisclosureGroup("report.measurementDetails") {
                Text("report.measurementNote").typography(.body)
                    .foregroundStyle(TherapyPalette.muted).padding(.top, 12)
            }
            .typography(.body).tint(TherapyPalette.green)
            TherapyButton(title: "report.delete", symbol: "trash", secondary: true) {
                Task {
                    await dependencies.home.delete(summary)
                    if dependencies.home.errorKey == nil {
                        router.popToRoot()
                        router.push(.reports)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionAchievements(_ summary: FingerSessionSummary) -> some View {
        let badges = PracticeAchievement.catalog.filter { badge in
            guard let award = dependencies.progress.award(for: badge) else {
                return false
            }
            return abs(award.earned.timeIntervalSince(summary.ended)) < 0.001
        }
        if !badges.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("achievement.thisSession").typography(.title2)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(badges) { badge in PracticeBadgeTile(badge: badge).frame(width: 180) }
                    }
                }
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
