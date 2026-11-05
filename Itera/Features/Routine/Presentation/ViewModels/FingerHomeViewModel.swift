//
//  FingerHomeViewModel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Observation
import Foundation

@MainActor
@Observable
final class FingerHomeViewModel {
    var routine: FingerRoutine
    private(set) var history: [FingerSessionSummary] = []
    private(set) var checkpoint: FingerSessionSummary?
    private(set) var errorKey: String?
    @ObservationIgnored private let repository: any FingerSessionRepository

    @ObservationIgnored private let routineRepository: any FingerRoutineRepository
    @ObservationIgnored private var loadedRoutine = false

    init(
        category: ExerciseCategory = .fingers,
        repository: any FingerSessionRepository,
        routineRepository: any FingerRoutineRepository
    ) {
        routine = FingerRoutine(category: category)
        self.repository = repository
        self.routineRepository = routineRepository
    }

    var repetitionSummary: String {
        String.localizedStringWithFormat(
            String(localized: "plan.repetitionFormat", bundle: AppLanguage.selected.resourceBundle),
            Int64(routine.sets), Int64(routine.repetitions)
        )
    }

    var movementSummary: String {
        String.localizedStringWithFormat(
            String(localized: "plan.movementFormat", bundle: AppLanguage.selected.resourceBundle), Int64(routine.exercises.count)
        )
    }

    func saveRoutine() async -> Bool {
        do {
            try await routineRepository.save(routine)
            errorKey = nil
            return true
        } catch {
            errorKey = "storage.error"
            return false
        }
    }

    func refresh() async {
        do {
            if !loadedRoutine {
                if let saved = try await routineRepository.load() {
                    routine = saved
                }
                loadedRoutine = true
            }
            checkpoint = try await repository.pending()
            history = try await repository.history()
            errorKey = nil
        } catch {
            errorKey = "storage.error"
        }
    }

    func delete(_ summary: FingerSessionSummary) async {
        do {
            try await repository.delete(summary.id)
            await refresh()
        } catch {
            errorKey = "storage.error"
        }
    }
}
