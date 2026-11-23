//
//  DailyPlanHistoryRepository.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

import Foundation

/// Reads the daily plan's saved days for the Progress calendar, and corrects a day when its
/// record of an exercise is deleted.
///
/// History declares this contract and Home's `LocalDailyPlanProgressRepository` fulfils it, so
/// History never names a Home type (as with `HistoryRecoveryServiceProtocol` in the other
/// direction).
protocol DailyPlanHistoryRepository: Sendable {
    /// Every saved day, oldest first; empty when nothing was saved yet. Throws for unreadable or
    /// unsupported data.
    func planHistory() async throws -> [DailyPlanDay]

    /// Drops `itemID` from the completed items saved for `day`; nothing changes when the day or
    /// item was never saved. Throws for unreadable or unsupported data, which is never replaced.
    func removeCompleted(_ itemID: String, on day: Date) async throws
}
