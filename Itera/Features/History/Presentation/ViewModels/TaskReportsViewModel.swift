//
//  TaskReportsViewModel.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class TaskReportsViewModel {
    private(set) var summaries: [SessionSummary] = []
    private(set) var loading = false
    private(set) var errorKey: String?
    /// Older summaries that could not be read; the readable ones are still listed.
    private(set) var unreadableCount = 0
    let category: TherapyCategory
    /// The exercises this history lists; by default the category's own.
    private let kinds: Set<TherapyKind>
    @ObservationIgnored private let repository: any SessionRepository

    init(category: TherapyCategory, kinds: Set<TherapyKind>? = nil, repository: any SessionRepository) {
        self.category = category
        self.kinds = kinds ?? Set(category.kinds)
        self.repository = repository
    }

    /// Every session with recorded movement: guided arm practice and the Balancing exercises.
    static func movementHistory(repository: any SessionRepository) -> TaskReportsViewModel {
        TaskReportsViewModel(
            category: .arm,
            kinds: Set(TherapyKind.allCases.filter(\.recordsMovement)),
            repository: repository
        )
    }

    /// The results of this history's exercises; sessions also hold other categories' work.
    func results(in summary: SessionSummary) -> [SessionActivityResult] {
        summary.results.filter { kinds.contains($0.activity.kind) }
    }

    func load() async {
        guard !loading else {
            return
        }
        loading = true
        defer { loading = false }
        do {
            summaries = try await repository.history().filter { summary in
                summary.routine.activities.contains { kinds.contains($0.kind) }
            }
            unreadableCount = await repository.unreadableHistoryCount()
            errorKey = nil
        } catch {
            errorKey = "towel.historyError"
        }
    }

    /// Deletes every listed session and its replays, keeping any that fail so they stay visible.
    func deleteAll() async {
        guard !loading else {
            return
        }

        errorKey = nil

        for summary in summaries {
            do {
                try await repository.delete(id: summary.id)
                summaries.removeAll { $0.id == summary.id }
            } catch {
                errorKey = "towel.deleteError"
            }
        }
    }

    func delete(_ id: UUID) async {
        guard !loading else {
            return
        }
        do {
            try await repository.delete(id: id)
            summaries.removeAll { $0.id == id }
            errorKey = nil
        } catch {
            errorKey = "towel.deleteError"
        }
    }
}
