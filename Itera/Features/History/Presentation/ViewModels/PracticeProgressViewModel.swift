//
//  PracticeProgressViewModel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class PracticeProgressViewModel {
    private(set) var progress = PracticeProgress()
    private(set) var awards: [AchievementAward] = []
    private(set) var week: [PracticeDay] = []
    private(set) var weekOffset = 0
    private(set) var errorKey: String?
    private(set) var loading = false
    private(set) var acknowledging = false
    @ObservationIgnored private let history: any FingerHistoryReading
    @ObservationIgnored private let repository: any AchievementRepository

    init(history: any FingerHistoryReading, repository: any AchievementRepository) {
        self.history = history
        self.repository = repository
        week = progress.week(offset: 0)
    }


    var pending: [PracticeAchievement] {
        let ids = Set(awards.filter { !$0.acknowledged }.map(\.id))
        return PracticeAchievement.catalog.filter { ids.contains($0.id) }
    }

    var next: PracticeAchievement? {
        let ids = Set(awards.map(\.id))
        return PracticeAchievement.catalog.first { !ids.contains($0.id) }
    }

    func refresh() async {
        guard !loading else {
            return
        }
        loading = true
        defer { loading = false }
        do {
            progress = PracticeProgress(history: try await history.history())
            week = progress.week(offset: weekOffset)
            awards = try await repository.merge(progress.candidates)
            errorKey = nil
        } catch {
            errorKey = "achievement.storageError"
        }
    }

    func moveWeek(_ delta: Int) {
        weekOffset = min(0, max(-520, weekOffset + delta))
        week = progress.week(offset: weekOffset)
    }

    func acknowledge() async -> Bool {
        guard !acknowledging else {
            return false
        }
        acknowledging = true
        defer { acknowledging = false }
        do {
            awards = try await repository.acknowledge(Set(pending.map(\.id)))
            errorKey = nil
            return true
        } catch {
            errorKey = "achievement.storageError"
            return false
        }
    }

    func award(for badge: PracticeAchievement) -> AchievementAward? {
        awards.first { $0.id == badge.id }
    }

    func title(for badge: PracticeAchievement) -> String {
        if let movement = badge.movement {
            return String(localized: String.LocalizationValue(movement.title))
        }
        return String.localizedStringWithFormat(
            String(localized: String.LocalizationValue("achievement.title." + badge.family.rawValue)),
            Int64(badge.target)
        )
    }
}
