//
//  FingerRoutineRepository.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

protocol FingerRoutineRepository: Sendable {
    func load() async throws -> FingerRoutine?
    func save(_ routine: FingerRoutine) async throws
}
