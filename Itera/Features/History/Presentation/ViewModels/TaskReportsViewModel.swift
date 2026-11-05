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
    @ObservationIgnored private let repository: any SessionRepository

    init(repository: any SessionRepository) { self.repository = repository }

    func load() async {
        guard !loading else {
            return
        }
        loading = true
        defer { loading = false }
        do {
            summaries = try await repository.history().filter {
                $0.routine.activities.contains { $0.kind == .foldTowel }
            }
            errorKey = nil
        } catch {
            errorKey = "towel.historyError"
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
