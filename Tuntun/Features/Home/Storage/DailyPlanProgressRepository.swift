//
//  DailyPlanProgressRepository.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

protocol DailyPlanProgressRepository: Sendable {
    /// Returns `nil` when nothing was saved yet; throws for unreadable or unsupported data.
    func load() async throws -> DailyPlanProgress?
    /// Every saved day, oldest first. An empty list means no exercise has ever been completed.
    func history() async throws -> [DailyPlanProgress]
    func save(_ progress: DailyPlanProgress) async throws
}
