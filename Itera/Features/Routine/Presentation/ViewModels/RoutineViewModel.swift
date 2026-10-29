//
//  RoutineViewModel.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class RoutineViewModel {
    var configuration = RoutineConfiguration()
    private(set) var failure: String?
    private(set) var loading = true
    private(set) var loadFailed = false
    private(set) var saving = false
    @ObservationIgnored private let repository: any RoutineRepository

    init(repository: any RoutineRepository) {
        self.repository = repository
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            if let saved = try await repository.load() {
                configuration = saved
            }
            failure = nil
            loadFailed = false
        } catch {
            failure = error.localizedDescription
            loadFailed = true
        }
    }

    func save() async -> Bool {
        guard !loadFailed, !loading, !saving, !configuration.exercises.isEmpty else {
            return false
        }
        saving = true
        defer { saving = false }
        do {
            try await repository.save(configuration)
            failure = nil
            return true
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    func deleteSaved() async {
        guard !saving, !loading, !loadFailed else { return }
        do {
            try await repository.delete()
            configuration = RoutineConfiguration()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    func add(_ kind: TherapyKind) {
        guard !configuration.exercises.contains(where: { $0.kind == kind }) else {
            return
        }
        configuration.exercises.append(
            RoutineExercise(kind: kind, sides: kind == .armRaise || kind == .elbowBend ? .both : .left)
        )
    }
}
