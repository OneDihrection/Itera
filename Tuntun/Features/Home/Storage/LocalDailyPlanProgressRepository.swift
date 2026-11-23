//
//  LocalDailyPlanProgressRepository.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import Foundation

/// Saves the daily plan's progress in `daily-plan-progress.json`, one entry per day.
///
/// Version 1 kept only the latest day, so earlier days were lost when a new day was saved.
/// Version 2 keeps every day (bounded by `keptDays`) so the Progress calendar can show which
/// days were completed; a version 1 file is read as a one-day history and upgraded on the next
/// save.
actor LocalDailyPlanProgressRepository: DailyPlanProgressRepository, DailyPlanHistoryRepository {
    /// About two years of daily entries: a few kilobytes, read once per Progress refresh.
    static let keptDays = 730

    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("daily-plan-progress.json")) {
        self.url = url
    }

    // MARK: - Records

    private struct VersionRecord: Codable {
        let version: Int
    }

    /// Version 1: only the latest day.
    private struct RecordV1: Codable {
        let version: Int
        let day: Date
        let completed: [String]
    }

    /// Version 2: every kept day, oldest first.
    private struct Record: Codable {
        let version: Int
        let days: [DayRecord]
    }

    private struct DayRecord: Codable {
        let day: Date
        let completed: [String]
        /// Empty for a day upgraded from version 1.
        let planned: [String]
    }

    // MARK: - DailyPlanProgressRepository

    /// The latest saved day; the plan itself decides whether it is still today.
    func load() throws -> DailyPlanProgress? {
        guard let latest = try loadDays()?.last else {
            return nil
        }

        return DailyPlanProgress(
            day: latest.day,
            completed: Set(latest.completed),
            planned: latest.planned
        )
    }

    func history() throws -> [DailyPlanProgress] {
        (try loadDays() ?? []).map { record in
            DailyPlanProgress(
                day: record.day,
                completed: Set(record.completed),
                planned: record.planned
            )
        }
    }

    /// Replaces the entry for the progress's day and keeps every other day.
    func save(_ progress: DailyPlanProgress) throws {
        // Never overwrite an unreadable or unsupported file with new progress.
        var days = try loadDays() ?? []

        let entry = DayRecord(
            day: progress.day,
            completed: progress.completed.sorted(),
            planned: progress.planned
        )

        days.removeAll { Calendar.current.isDate($0.day, inSameDayAs: progress.day) }
        days.append(entry)
        days.sort { $0.day < $1.day }
        days = Array(days.suffix(Self.keptDays))

        try AtomicJSONFiles.write(Record(version: 2, days: days), to: url)
    }

    // MARK: - DailyPlanHistoryRepository

    func planHistory() throws -> [DailyPlanDay] {
        let standardIDs = Set(DailyPlan.standard.map(\.id))

        return (try loadDays() ?? []).map { record in
            DailyPlanDay(
                day: record.day,
                // A day saved before the plan recorded its items is judged against the
                // standard plan.
                planned: record.planned.isEmpty ? standardIDs : Set(record.planned),
                completed: Set(record.completed)
            )
        }
    }

    /// Rewrites only the matching day, and only when it lists the item.
    func removeCompleted(_ itemID: String, on day: Date) throws {
        guard var days = try loadDays(),
              let index = days.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }),
              days[index].completed.contains(itemID)
        else {
            return
        }

        let record = days[index]

        days[index] = DayRecord(
            day: record.day,
            completed: record.completed.filter { $0 != itemID },
            planned: record.planned
        )

        try AtomicJSONFiles.write(Record(version: 2, days: days), to: url)
    }

    // MARK: - Reading

    /// `nil` when nothing was saved yet; throws for unreadable or unsupported data.
    private func loadDays() throws -> [DayRecord]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let version = try AtomicJSONFiles.read(VersionRecord.self, from: url).version

        switch version {
        case 1:
            let record = try AtomicJSONFiles.read(RecordV1.self, from: url)
            return [DayRecord(day: record.day, completed: record.completed, planned: [])]
        case 2:
            return try AtomicJSONFiles.read(Record.self, from: url).days
        default:
            throw StorageError.unsupported
        }
    }

    private enum StorageError: Error {
        case unsupported
    }
}
