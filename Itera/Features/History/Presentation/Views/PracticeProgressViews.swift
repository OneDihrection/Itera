//
//  PracticeProgressViews.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct PracticeProgressSection: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    private var model: PracticeProgressViewModel { dependencies.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            streak
            weekControls
            if typeSize.isAccessibilitySize {
                repetitionsChart
                minutesChart
            } else {
                HStack(alignment: .top, spacing: 22) {
                    repetitionsChart
                    minutesChart
                }
            }
            badgePreview
            if let key = model.errorKey {
                TherapyError(key: key)
                TherapyButton(title: "action.retry", secondary: true) { Task { await model.refresh() } }
            }
        }
    }

    private var streak: some View {
        TherapyCard(color: TherapyPalette.secondary) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 20) {
                    streakHeading
                    streakMetrics
                }
            } else {
                HStack(spacing: 26) {
                    Image(systemName: "flame.fill").typography(size: 60, weight: .bold)
                        .foregroundStyle(TherapyPalette.primary).accessibilityHidden(true)
                    streakHeading
                    Spacer()
                    streakMetrics.frame(width: 280)
                }
            }
        }
    }

    private var streakHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("progress.streak").typography(.title2)
            Text("progress.restKindness").typography(.footnote).foregroundStyle(TherapyPalette.muted)
        }
    }

    private var streakMetrics: some View {
        HStack(spacing: 22) {
            TherapyMetric(title: "progress.currentDays", value: String(model.progress.currentStreak))
            TherapyMetric(title: "progress.bestDays", value: String(model.progress.bestStreak))
        }
    }

    private var weekControls: some View {
        HStack(spacing: 18) {
            Text("progress.week").typography(.title)
            Spacer()
            Button { model.moveWeek(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 64, height: 64)
                    .background(TherapyPalette.surface, in: Circle())
            }.accessibilityLabel("progress.previousWeek")
            if let first = model.week.first, let last = model.week.last {
                Text(first.date..<last.date, format: .interval.day().month(.abbreviated))
                    .typography(.body).monospacedDigit()
            }
            Button { model.moveWeek(1) } label: {
                Image(systemName: "chevron.right").frame(width: 64, height: 64)
                    .background(TherapyPalette.surface, in: Circle())
            }
            .accessibilityLabel("progress.nextWeek")
            .disabled(model.weekOffset == 0)
        }
        .buttonStyle(TherapySoundButtonStyle())
    }

    private var repetitionsChart: some View {
        TherapyProgressChart(title: "progress.repetitions", points: model.week.map {
            TherapyChartPoint(date: $0.date, value: Double($0.repetitions))
        })
    }

    private var minutesChart: some View {
        TherapyProgressChart(title: "progress.minutes", points: model.week.map {
            TherapyChartPoint(date: $0.date, value: $0.seconds / 60)
        }, line: true)
    }

    private var badgePreview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("achievement.title").typography(.title)
                Spacer()
                Button("achievement.seeAll") { router.push(.achievements) }
                    .typography(.headline).frame(minHeight: 64)
            }
            .buttonStyle(TherapySoundButtonStyle())
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(previewBadges) { badge in
                        PracticeBadgeTile(badge: badge)
                            .frame(width: 170)
                    }
                }.padding(.vertical, 8)
            }
            if let next = model.next {
                HStack {
                    Text("achievement.next").typography(.headline)
                    Text(verbatim: model.title(for: next)).typography(.body)
                    Spacer()
                    Text(verbatim: "\(min(next.target, model.progress.value(for: next)))/\(next.target)")
                        .typography(.headline).monospacedDigit()
                }
                .padding(20).background(TherapyPalette.secondary, in: RoundedRectangle(cornerRadius: 22))
            }
        }
    }

    private var previewBadges: [PracticeAchievement] {
        let earned = PracticeAchievement.catalog.filter { model.award(for: $0) != nil }
        let locked = PracticeAchievement.catalog.filter { model.award(for: $0) == nil }
        return Array((earned + locked).prefix(7))
    }
}

struct PracticeBadgeTile: View {
    let badge: PracticeAchievement
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        let model = dependencies.progress
        let earned = model.award(for: badge) != nil
        Button { router.presentSheet(.achievement(badge.id)) } label: {
            VStack(spacing: 14) {
                TherapyBadge(symbol: badge.symbol, value: String(badge.target), earned: earned)
                Text(verbatim: model.title(for: badge)).typography(.headline)
                    .multilineTextAlignment(.center)
                Text(earned ? "achievement.earned" : "achievement.locked").typography(.footnote)
                    .foregroundStyle(TherapyPalette.muted)
            }
            .foregroundStyle(TherapyPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
            .padding(14)
            .background(TherapyPalette.surface, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(TherapySoundButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

struct PracticeAchievementsView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("achievement.encouragement").typography(.title)
                Text("achievement.smallSteps").typography(.body).foregroundStyle(TherapyPalette.muted)
                ForEach(AchievementFamily.allCases, id: \.self) { family in
                    VStack(alignment: .leading, spacing: 18) {
                        Text(LocalizedStringKey(family.title)).typography(.title2)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 20)], spacing: 20) {
                            ForEach(PracticeAchievement.catalog.filter { $0.family == family }) { badge in
                                PracticeBadgeTile(badge: badge)
                            }
                        }
                    }
                }
            }.padding(30)
        }
        .foregroundStyle(TherapyPalette.ink).background(TherapyPalette.cream)
        .navigationTitle("achievement.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await dependencies.progress.refresh() }
    }
}

struct PracticeAchievementDetailView: View {
    let id: String
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        ScrollView {
            if let badge = PracticeAchievement.catalog.first(where: { $0.id == id }) {
                detail(badge)
            }
        }
        .foregroundStyle(TherapyPalette.ink).background(TherapyPalette.cream)
        .presentationDetents([.large])
    }

    private func detail(_ badge: PracticeAchievement) -> some View {
        let model = dependencies.progress
        let award = model.award(for: badge)
        return VStack(spacing: 26) {
            TherapyBadge(symbol: badge.symbol, value: String(badge.target), earned: award != nil, size: 190)
            Text(verbatim: model.title(for: badge)).typography(.largeTitle).multilineTextAlignment(.center)
            if let award {
                Text("achievement.earned").typography(.headline)
                Text(award.earned, format: .dateTime.day().month(.wide).year()).typography(.body)
                Text("achievement.encouragement").typography(.title2).multilineTextAlignment(.center)
            } else {
                Text(LocalizedStringKey(badge.family.title)).typography(.body)
                Text(verbatim: "\(min(badge.target, model.progress.value(for: badge)))/\(badge.target)")
                    .typography(.largeTitle).monospacedDigit()
                Text("achievement.smallSteps").typography(.body).multilineTextAlignment(.center)
            }
            TherapyButton(title: "action.done") { router.dismissSheet() }
        }.padding(40).frame(maxWidth: 650).frame(maxWidth: .infinity)
    }
}

struct AchievementCelebrationView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Text("achievement.new").typography(.largeTitle).multilineTextAlignment(.center)
                Text("achievement.encouragement").typography(.body).multilineTextAlignment(.center)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 24) {
                    ForEach(dependencies.progress.pending) { badge in
                        VStack(spacing: 12) {
                            TherapyBadge(symbol: badge.symbol, value: String(badge.target), earned: true, size: 110)
                            Text(verbatim: dependencies.progress.title(for: badge))
                                .typography(.headline).multilineTextAlignment(.center)
                        }
                    }
                }
                if let error = dependencies.progress.errorKey { TherapyError(key: error) }
            }.padding(36)
        }
        .foregroundStyle(TherapyPalette.ink).background(TherapyPalette.cream)
        .safeAreaInset(edge: .bottom) {
            TherapyButton(title: "achievement.keepGoing", symbol: "checkmark", disabled: dependencies.progress.acknowledging) {
                Task {
                    if await dependencies.progress.acknowledge() {
                        router.dismissSheet()
                    }
                }
            }
            .padding(24).background(TherapyPalette.cream)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}
