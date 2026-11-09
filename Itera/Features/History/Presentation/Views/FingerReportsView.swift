//
//  FingerReportsView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

/// The Progress tab: this week at a glance, the current challenge, badges and history.
struct TMFingerReportsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.locale) private var locale
    @AppStorage(PracticePreferences.patientName) private var patientName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                weekRange
                weekSummary
                challengeSection
                TMTherapyButton(title: "towel.history", symbol: "square.stack.3d.up") {
                    router.push(.taskReports)
                }
                historySection
            }
            // The system page margin keeps content aligned under the large navigation title.
            .scenePadding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas)
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.large)
        .task { await refreshProgress() }
    }

    // MARK: - Header

    @ViewBuilder
    private var weekRange: some View {
        if let first = week.first?.date, let last = week.last?.date {
            Text(first..<last, format: .interval.day().month(.abbreviated).year())
                .typography(size: 24, weight: .regular, relativeTo: .title3)
                .foregroundStyle(TherapyPalette.muted)
        }
    }

    /// "Progres Bu Yuli" when a name is set in Settings, otherwise "Progres".
    private var headerTitle: Text {
        let name = patientName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return Text("progress.title")
        }

        return Text("progress.titleName \(name)")
    }

    // MARK: - Week

    private var week: [PracticeDay] {
        dependencies.progress.week
    }

    private var weekSummary: some View {
        let practisedDays = week.filter { $0.sessions > 0 }.count
        let sessions = week.reduce(0) { $0 + $1.sessions }
        let repetitions = week.reduce(0) { $0 + $1.repetitions }
        let minutes = Int((week.reduce(0) { $0 + $1.seconds } / 60).rounded())

        return TMTherapyWeekSummary(
            title: "progress.weekDays \(practisedDays)",
            detail: "progress.weekDetail \(sessions) \(repetitions) \(minutes)",
            days: week.map { day in
                TMTherapyWeekSummary.Day(
                    id: day.date,
                    label: day.date.formatted(.dateTime.day().month(.abbreviated).locale(locale)),
                    caption: day.sessions > 0 ? "progress.daySessions \(day.sessions)" : "progress.dayEmpty",
                    done: day.sessions > 0
                )
            }
        )
    }

    // MARK: - Challenge and badges

    @ViewBuilder
    private var challengeSection: some View {
        let progress = dependencies.progress
        let challenge = progress.sessionChallenge
        let latest = progress.latestAward

        if challenge != nil || latest != nil {
            VStack(alignment: .leading, spacing: 16) {
                Text("progress.challenges")
                    .typography(size: 24, weight: .semiBold, relativeTo: .title2)
                    .accessibilityAddTraits(.isHeader)

                if let challenge {
                    TMTherapyChallengeCard(
                        title: "progress.challenge.sessions",
                        progressText: "progress.challengeProgress \(min(progress.progress.sessions, challenge.target)) \(challenge.target)",
                        status: "progress.challengeActive",
                        targetText: "progress.challengeTarget \(progress.title(for: challenge))",
                        completed: progress.progress.sessions,
                        total: challenge.target
                    )
                }

                if let latest {
                    Button {
                        router.push(.achievements)
                    } label: {
                        TMTherapyAchievementRow(
                            title: progress.title(for: latest.badge),
                            subtitle: earnedText(latest.award.earned),
                            count: "progress.badgeCount \(progress.awards.count)"
                        )
                    }
                    .buttonStyle(TMTherapySoundButtonStyle())
                }
            }
        }
    }

    private func earnedText(_ date: Date) -> String {
        let formatted = date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        return String(localized: "progress.badgeEarned \(formatted)", bundle: AppLanguage.selected.resourceBundle)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline) {
                Text("reports.history")
                    .typography(size: 32, weight: .bold, relativeTo: .title)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Text("progress.sessionsRecorded \(dependencies.home.history.count)")
                    .typography(size: 20, weight: .regular, relativeTo: .subheadline)
                    .foregroundStyle(TherapyPalette.muted)
            }

            if let error = dependencies.home.errorKey {
                TMTherapyError(key: error)
                TMTherapyButton(title: "action.retry", secondary: true, pill: true) {
                    Task { await dependencies.home.refresh() }
                }
            }

            if dependencies.home.history.isEmpty {
                emptyHistory
            } else {
                ForEach(dependencies.home.history) { summary in
                    Button {
                        router.push(.report(summary.id))
                    } label: {
                        TMFingerHistoryCard(summary: summary)
                    }
                    .buttonStyle(TMTherapySoundButtonStyle())
                }
            }
        }
    }

    private var emptyHistory: some View {
        TMTherapyCard(color: TherapyPalette.canvas, outlined: true) {
            VStack(alignment: .leading, spacing: 16) {
                Text("reports.empty").typography(.title2)
                Text("reports.emptyDetail").typography(.body)
                TMTherapyButton(title: "home.startExercise", symbol: "play.fill", pill: true) {
                    router.popToRoot()
                }
                .frame(maxWidth: 360)
            }
        }
    }

    private func refreshProgress() async {
        await dependencies.home.refresh()
        await dependencies.progress.refresh()
        if !dependencies.progress.pending.isEmpty {
            router.presentAchievementCelebration()
        }
    }
}

// MARK: - History card

/// One saved session: its date and outcome, then the therapist's plan against what was done.
private struct TMFingerHistoryCard: View {
    let summary: FingerSessionSummary

    var body: some View {
        TMTherapyCard(color: TherapyPalette.canvas, outlined: true, padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(summary.started, format: .dateTime.weekday(.wide).day().month(.abbreviated).year())
                        .typography(size: 24, weight: .semiBold, relativeTo: .headline)
                    Spacer(minLength: 12)
                    Label(LocalizedStringKey("progress.outcome." + summary.outcome.rawValue), systemImage: outcomeSymbol)
                        .typography(size: 20, weight: .medium, relativeTo: .subheadline)
                }

                ForEach(performedResults) { result in
                    resultRow(result)
                    Divider()
                }

                if let feeling = summary.feeling {
                    HStack(spacing: 6) {
                        Text("progress.feeling")
                        Text(LocalizedStringKey(feeling.title))
                    }
                    .typography(size: 20, weight: .regular, relativeTo: .subheadline)
                    .foregroundStyle(TherapyPalette.muted)
                }
            }
            .foregroundStyle(TherapyPalette.ink)
            .multilineTextAlignment(.leading)
        }
    }

    /// Skipped and untouched movements stay in the detailed report, not this overview.
    private var performedResults: [FingerExerciseResult] {
        summary.results.filter { $0.repetitions > 0 && !$0.skipped }
    }

    private var outcomeSymbol: String {
        summary.outcome == .completed ? "checkmark" : "clock.arrow.circlepath"
    }

    private func resultRow(_ result: FingerExerciseResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "hand.raised")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(result.kind.title))
                        .typography(size: 22, weight: .semiBold, relativeTo: .headline)
                    Text("progress.duration \(minutes(result.activeSeconds))")
                        .typography(size: 18, weight: .regular, relativeTo: .subheadline)
                        .foregroundStyle(TherapyPalette.muted)
                }
            }

            HStack(alignment: .top, spacing: 24) {
                column(title: "progress.plan", value: plan)
                column(title: "progress.done", value: done(result))
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

    /// Whole minutes, with any practice shorter than a minute shown as one.
    private func minutes(_ seconds: Double) -> Int {
        guard seconds > 0 else {
            return 0
        }

        return max(1, Int((seconds / 60).rounded()))
    }
}

struct TMFingerReportDetailView: View {
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
            sessionAchievements(summary)
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
            Text("report.cameraNoteShort").typography(.footnote).foregroundStyle(TherapyPalette.muted)
            DisclosureGroup("report.measurementDetails") {
                Text("report.measurementNote").typography(.body)
                    .foregroundStyle(TherapyPalette.muted).padding(.top, 12)
            }
            .typography(.body).tint(TherapyPalette.green)
            TMTherapyButton(title: "report.delete", symbol: "trash", secondary: true) {
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
                        ForEach(badges) { badge in TMPracticeBadgeTile(badge: badge).frame(width: 180) }
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
