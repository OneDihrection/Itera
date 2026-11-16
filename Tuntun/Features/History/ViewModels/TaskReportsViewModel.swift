//
//  TaskReportsViewModel.swift
//  Tuntun
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
    private let kinds = Set(TherapyKind.allCases.filter(\.recordsMovement))
    @ObservationIgnored private let repository: any SessionRepository

    init(repository: any SessionRepository) {
        self.repository = repository
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
}
