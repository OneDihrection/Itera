//
//  LocalFingerSessionRepository.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

actor LocalFingerSessionRepository: FingerSessionRepository {
    private let folder: URL
    private var checkpointURL: URL { folder.appendingPathComponent("active.json") }

    init() {
        folder = URL.applicationSupportDirectory.appendingPathComponent("FingerSessions", isDirectory: true)
    }

    func checkpoint(_ summary: FingerSessionSummary) throws {
        // A queued checkpoint cannot resurrect a finalized session.
        if FileManager.default.fileExists(atPath: file(summary.id).path) {
            _ = try read(file(summary.id))
            return
        }
        if FileManager.default.fileExists(atPath: checkpointURL.path) {
            var previous = try read(checkpointURL)
            if previous.id != summary.id {
                previous.outcome = .interrupted
                previous.ended = Date()
                try finalize(previous)
            }
        }
        try save(summary, to: checkpointURL)
    }

    func pending() throws -> FingerSessionSummary? {
        guard FileManager.default.fileExists(atPath: checkpointURL.path) else {
            return nil
        }
        let summary = try read(checkpointURL)
        let finalizedURL = file(summary.id)
        if FileManager.default.fileExists(atPath: finalizedURL.path) {
            _ = try read(finalizedURL)
            try FileManager.default.removeItem(at: checkpointURL)
            return nil
        }
        if summary.outcome == .savedForLater {
            return summary
        }
        var interrupted = summary
        interrupted.outcome = .interrupted
        interrupted.ended = Date()
        try finalize(interrupted)
        return nil
    }

    func finalize(_ summary: FingerSessionSummary) throws {
        try save(summary, to: file(summary.id))
        if FileManager.default.fileExists(atPath: checkpointURL.path) {
            let pending = try read(checkpointURL)
            if pending.id == summary.id {
                try FileManager.default.removeItem(at: checkpointURL)
            }
        }
    }

    func history() throws -> [FingerSessionSummary] {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "active.json" }
            .map(read).sorted { $0.started > $1.started }
    }

    func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: file(id)) }

    private func file(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".json") }

    private func read(_ url: URL) throws -> FingerSessionSummary {
        try AtomicJSONFiles.read(FingerSessionRecord.self, from: url).domain()
    }

    private func save(_ summary: FingerSessionSummary, to url: URL) throws {
        try AtomicJSONFiles.write(FingerSessionRecord(summary), to: url)
    }
}
