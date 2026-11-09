//
//  LocalDailyPlanProgressRepository.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import Foundation

actor LocalDailyPlanProgressRepository: DailyPlanProgressRepository {
    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("daily-plan-progress.json")) {
        self.url = url
    }

    private struct Record: Codable {
        let version: Int
        let day: Date
        let completed: [String]
    }

    func load() throws -> DailyPlanProgress? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let record = try AtomicJSONFiles.read(Record.self, from: url)

        guard record.version == 1 else {
            throw StorageError.unsupported
        }

        return DailyPlanProgress(day: record.day, completed: Set(record.completed))
    }

    func save(_ progress: DailyPlanProgress) throws {
        // Never overwrite an unreadable or unsupported file with new progress.
        _ = try load()

        let record = Record(
            version: 1,
            day: progress.day,
            completed: progress.completed.sorted()
        )
        try AtomicJSONFiles.write(record, to: url)
    }

    private enum StorageError: Error {
        case unsupported
    }
}
