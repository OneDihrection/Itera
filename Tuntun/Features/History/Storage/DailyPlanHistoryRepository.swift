//
//  DailyPlanHistoryRepository.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

/// Reads the daily plan's saved days for the Progress calendar.
///
/// History declares this contract and Home's `LocalDailyPlanProgressRepository` fulfils it, so
/// History never names a Home type (as with `HistoryRecoveryServiceProtocol` in the other
/// direction).
protocol DailyPlanHistoryRepository: Sendable {
    /// Every saved day, oldest first; empty when nothing was saved yet. Throws for unreadable or
    /// unsupported data.
    func planHistory() async throws -> [DailyPlanDay]
}
