//
//  LocalSessionRepository.swift
//  Tuntun
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
    private let directory: URL
    private var activeURL: URL { directory.appendingPathComponent("active.json") }
    private static let keyRepsSuffix = ".reps.json"
    private static let clipsSuffix = ".clips"
    /// Summaries the last `history()` call could not read.
    private var unreadableCount = 0

    init(directory: URL) { self.directory = directory }

    func recoverInterrupted() throws {
        guard FileManager.default.fileExists(atPath: activeURL.path) else {
            return
        }
        let record = try AtomicJSONFiles.read(Record<SessionCheckpoint>.self, from: activeURL)
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
        ).filter {
            $0.pathExtension == "json"
                && $0.lastPathComponent != "active.json"
                && !$0.lastPathComponent.hasSuffix(Self.keyRepsSuffix)
        }
        // One unreadable summary must not hide every other session; it is logged and counted.
        var summaries: [SessionSummary] = []
        unreadableCount = 0

        for url in urls {
            do {
                let record = try AtomicJSONFiles.read(Record<SessionSummary>.self, from: url)

                guard record.version == 1 else {
                    throw StorageError.unsupportedVersion
                }

                summaries.append(record.value)
            } catch {
                unreadableCount += 1
                LogManager.shared.error("Session history skipped \(url.lastPathComponent)", error: error, category: .storage)
            }
        }

        return summaries.sorted { $0.startedAt > $1.startedAt }
    }

    func unreadableHistoryCount() -> Int {
        unreadableCount
    }

    func delete(id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let keyRepsURL = keyRepsURL(for: id)
        if FileManager.default.fileExists(atPath: keyRepsURL.path) {
            try FileManager.default.removeItem(at: keyRepsURL)
        }

        let clipsURL = clipsDirectory(for: id)
        if FileManager.default.fileExists(atPath: clipsURL.path) {
            try FileManager.default.removeItem(at: clipsURL)
        }
    }

    func checkpoint(_ value: SessionCheckpoint) throws {
        try AtomicJSONFiles.write(Record(version: 1, value: value), to: activeURL)
    }

    func finalize(_ value: SessionSummary) throws {
        let url = directory.appendingPathComponent(value.id.uuidString + ".json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try AtomicJSONFiles.write(Record(version: 1, value: value), to: url)
        }
        if FileManager.default.fileExists(atPath: activeURL.path) {
            let record = try AtomicJSONFiles.read(Record<SessionCheckpoint>.self, from: activeURL)
            guard record.version == 1 else { throw StorageError.unsupportedVersion }
            if record.value.id == value.id { try FileManager.default.removeItem(at: activeURL) }
        }
    }

    // MARK: - Key repetitions

    /// Skeletons live in their own file so history never decodes them. An unreadable file is
    /// reported, never replaced, so earlier replays are not silently lost.
    func saveKeyReps(_ value: ActivityKeyReps, sessionID: UUID) throws {
        var record = try readKeyReps(sessionID: sessionID) ?? KeyRepRecord(sessionID: sessionID)
        record.upsert(value)
        try AtomicJSONFiles.write(record, to: keyRepsURL(for: sessionID))
    }

    func keyReps(sessionID: UUID) throws -> [ActivityKeyReps] {
        try readKeyReps(sessionID: sessionID)?.domain() ?? []
    }

    private func readKeyReps(sessionID: UUID) throws -> KeyRepRecord? {
        let url = keyRepsURL(for: sessionID)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let record = try AtomicJSONFiles.read(KeyRepRecord.self, from: url)

        guard record.version == KeyRepRecord.currentVersion, record.sessionID == sessionID else {
            throw StorageError.unsupportedVersion
        }

        return record
    }

    // MARK: - Key-repetition clips

    /// Clips live in a per-session folder, one file per repetition, named
    /// `<execution id>-r<repetition>.mp4`. Each is written whole and moved into place.
    ///
    /// Nonisolated so encoding, which takes seconds, never holds the actor: checkpoints and the
    /// final summary are not queued behind it. It touches only its own new files.
    nonisolated func saveRepClips(_ clips: [Int: [RepClipFrame]], for keyReps: ActivityKeyReps, sessionID: UUID) async throws {
        let folder = clipsDirectory(for: sessionID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for rep in keyReps.reps {
            guard let frames = clips[rep.metrics.repNumber], !frames.isEmpty else {
                continue
            }

            let url = clipURL(
                sessionID: sessionID,
                executionID: keyReps.executionID,
                repNumber: rep.metrics.repNumber
            )
            try await RepClipWriter.write(frames, to: url)
        }
    }

    func repClipURLs(sessionID: UUID) -> [UUID: [Int: URL]] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: clipsDirectory(for: sessionID),
            includingPropertiesForKeys: nil
        )) ?? []
        var result: [UUID: [Int: URL]] = [:]

        for url in files where url.pathExtension == "mp4" {
            let name = url.deletingPathExtension().lastPathComponent

            guard let separator = name.range(of: "-r", options: .backwards),
                  let executionID = UUID(uuidString: String(name[..<separator.lowerBound])),
                  let repNumber = Int(name[separator.upperBound...])
            else {
                continue
            }

            result[executionID, default: [:]][repNumber] = url
        }

        return result
    }

    func deleteRepClip(sessionID: UUID, executionID: UUID, repNumber: Int) throws {
        let url = clipURL(sessionID: sessionID, executionID: executionID, repNumber: repNumber)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }

    nonisolated private func clipURL(sessionID: UUID, executionID: UUID, repNumber: Int) -> URL {
        clipsDirectory(for: sessionID)
            .appendingPathComponent("\(executionID.uuidString)-r\(repNumber).mp4")
    }

    nonisolated private func clipsDirectory(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + Self.clipsSuffix, isDirectory: true)
    }

    private func keyRepsURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + Self.keyRepsSuffix)
    }

    private enum StorageError: Error { case unsupportedVersion }
}
