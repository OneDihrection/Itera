//
//  RoutineRepository.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

protocol RoutineRepository: Sendable {
    func load() async throws -> RoutineConfiguration?
    func save(_ routine: RoutineConfiguration) async throws
    func delete() async throws
}
