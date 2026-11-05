//
//  LocalSessionRepository.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

/// Actor serialization and atomic replacement keep checkpoints ordered and summaries idempotent.
actor LocalSessionRepository: SessionRepository {
    private struct Record<Value: Codable>: Codable {
        let version: Int
        let value: Value
    }
    private let storage = AtomicFileStorage()
    private let directory: URL
    private var activeURL: URL { directory.appendingPathComponent("active.json") }

    init(directory: URL) { self.directory = directory }

    func recoverInterrupted() throws {
        guard FileManager.default.fileExists(atPath: activeURL.path) else {
            return
        }
        let record = try storage.read(Record<SessionCheckpoint>.self, from: activeURL)
        guard record.version == 1 else { throw StorageError.unsupportedVersion }
        let checkpoint = record.value
        var results = checkpoint.results
        // One activity now has one result per set. Never index the routine by result count.
        for activity in checkpoint.routine.activities {
            let recorded = results.filter { $0.activity.id == activity.id }
            if recorded.contains(where: { $0.outcome != .completed }) {
                continue
            }
            let completedSets = recorded.count
            guard completedSets < activity.sets else { continue }
            results.append(
                SessionActivityResult(
                    executionID: UUID(), activity: activity,
                    outcome: .interrupted, completedWork: 0,
                    setNumber: completedSets + 1))
            break
        }
        try finalize(
            SessionSummary(
                id: checkpoint.id, routine: checkpoint.routine, startedAt: checkpoint.startedAt,
                endedAt: Date(), stopped: true, interrupted: true, results: results))
    }

    func history() throws -> [SessionSummary] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" && $0.lastPathComponent != "active.json" }
        return try urls.map { url in
            let record = try storage.read(Record<SessionSummary>.self, from: url)
            guard record.version == 1 else { throw StorageError.unsupportedVersion }
            return record.value
        }.sorted { $0.startedAt > $1.startedAt }
    }

    func delete(id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func checkpoint(_ value: SessionCheckpoint) throws {
        try write(Record(version: 1, value: value), to: activeURL)
    }

    func finalize(_ value: SessionSummary) throws {
        let url = directory.appendingPathComponent(value.id.uuidString + ".json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try write(Record(version: 1, value: value), to: url)
        }
        if FileManager.default.fileExists(atPath: activeURL.path) {
            let record = try storage.read(Record<SessionCheckpoint>.self, from: activeURL)
            guard record.version == 1 else { throw StorageError.unsupportedVersion }
            if record.value.id == value.id { try FileManager.default.removeItem(at: activeURL) }
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try storage.write(value, to: url)
    }

    private enum StorageError: Error { case unsupportedVersion }
}
