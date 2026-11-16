//
//  RoutineViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class RoutineViewModel {
    var configuration = RoutineConfiguration()
    @ObservationIgnored private let repository: any RoutineRepository

    init(repository: any RoutineRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            if let saved = try await repository.load() {
                configuration = saved
            }
        } catch {
            // Keep the in-memory configuration without replacing unreadable saved data.
        }
    }
}
