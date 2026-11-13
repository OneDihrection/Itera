//
//  LocalFingerSessionRepository.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

actor LocalFingerSessionRepository: FingerSessionRepository {
    private static let keyRepsSuffix = ".reps.json"
    private static let clipsSuffix = ".clips"
    private let folder: URL
    private let checkpointName: String
    private var checkpointURL: URL { folder.appendingPathComponent(checkpointName) }

    /// Every category shares one history folder; each keeps its own saved-for-later checkpoint.
    init(category: ExerciseCategory = .fingers) {
        folder = URL.applicationSupportDirectory.appendingPathComponent("FingerSessions", isDirectory: true)
        checkpointName = category == .fingers ? "active.json" : "active-\(category.rawValue).json"
    }

    func checkpoint(_ summary: FingerSessionSummary) throws {
        // A queued checkpoint cannot resurrect a finalized session.
        if FileManager.default.fileExists(atPath: file(summary.id).path) {
            _ = try read(file(summary.id))
            return
        }
        if FileManager.default.fileExists(atPath: checkpointURL.path),
           var previous = readableCheckpoint() {
            if previous.id != summary.id {
                previous.outcome = .interrupted
                previous.ended = Date()
                try finalize(previous)
            }
        }
        try save(summary, to: checkpointURL)
    }

    func pending() throws -> FingerSessionSummary? {
        guard FileManager.default.fileExists(atPath: checkpointURL.path),
              let summary = readableCheckpoint() else {
            return nil
        }
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
        // The session is saved; an unreadable leftover checkpoint must not turn that into a failure.
        if FileManager.default.fileExists(atPath: checkpointURL.path),
           let pending = readableCheckpoint(),
           pending.id == summary.id {
            try FileManager.default.removeItem(at: checkpointURL)
        }
    }

    func history() throws -> [FingerSessionSummary] {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return []
        }
        // One unreadable session file is skipped, untouched, rather than hiding every other session.
        return try historyFiles()
            .compactMap(readOrLog)
            .sorted { $0.started > $1.started }
    }

    func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: file(id))
        try removeIfPresent(keyRepsURL(for: id))
        try removeIfPresent(clipsDirectory(for: id))
    }

    func deleteHistory() throws {
        for url in try historyFiles() + sidecars() {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func historyFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter {
                $0.pathExtension == "json"
                    && !$0.lastPathComponent.hasPrefix("active")
                    && !$0.lastPathComponent.hasSuffix(Self.keyRepsSuffix)
            }
    }

    /// Replay files and clip folders of every session in the shared folder.
    private func sidecars() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter {
                $0.lastPathComponent.hasSuffix(Self.keyRepsSuffix)
                    || $0.lastPathComponent.hasSuffix(Self.clipsSuffix)
            }
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Key repetitions

    /// Skeletons live in their own file so history never decodes them. An unreadable file is
    /// reported, never replaced, so earlier replays are not silently lost.
    func saveKeyReps(_ value: FingerKeyReps, sessionID: UUID) throws {
        var record = try readKeyReps(sessionID: sessionID) ?? FingerKeyRepRecord(sessionID: sessionID)
        record.upsert(value)
        try AtomicJSONFiles.write(record, to: keyRepsURL(for: sessionID))
    }

    func keyReps(sessionID: UUID) throws -> [FingerKeyReps] {
        try readKeyReps(sessionID: sessionID)?.domain() ?? []
    }

    private func readKeyReps(sessionID: UUID) throws -> FingerKeyRepRecord? {
        let url = keyRepsURL(for: sessionID)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let record = try AtomicJSONFiles.read(FingerKeyRepRecord.self, from: url)

        guard record.version == FingerKeyRepRecord.currentVersion, record.sessionID == sessionID else {
            throw KeyRepError.unsupportedVersion
        }

        return record
    }

    /// One file per repetition, named `<exercise>-s<set>-r<repetition>.mp4`, each written whole
    /// and moved into place.
    func saveRepClips(_ clips: [Int: [RepClipFrame]], for keyReps: FingerKeyReps, sessionID: UUID) async throws {
        let directory = clipsDirectory(for: sessionID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for rep in keyReps.reps {
            guard let frames = clips[rep.metrics.repNumber], !frames.isEmpty else {
                continue
            }

            let name = "\(keyReps.exercise.rawValue)-s\(keyReps.setNumber)-r\(rep.metrics.repNumber).mp4"
            try await RepClipWriter.write(frames, to: directory.appendingPathComponent(name))
        }
    }

    func repClipURLs(sessionID: UUID) -> [FingerRepClipKey: URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: clipsDirectory(for: sessionID),
            includingPropertiesForKeys: nil
        )) ?? []
        var result: [FingerRepClipKey: URL] = [:]

        for url in files where url.pathExtension == "mp4" {
            let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: "-")

            guard parts.count == 3,
                  let exercise = FingerExercise(rawValue: parts[0]),
                  parts[1].hasPrefix("s"),
                  parts[2].hasPrefix("r"),
                  let setNumber = Int(parts[1].dropFirst()),
                  let repNumber = Int(parts[2].dropFirst())
            else {
                continue
            }

            result[FingerRepClipKey(exercise: exercise, setNumber: setNumber, repNumber: repNumber)] = url
        }

        return result
    }

    private func keyRepsURL(for id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString + Self.keyRepsSuffix)
    }

    private func clipsDirectory(for id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString + Self.clipsSuffix, isDirectory: true)
    }

    private enum KeyRepError: Error { case unsupportedVersion }

    private func file(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".json") }

    private func read(_ url: URL) throws -> FingerSessionSummary {
        try AtomicJSONFiles.read(FingerSessionRecord.self, from: url).domain()
    }

    private func readOrLog(_ url: URL) -> FingerSessionSummary? {
        do {
            return try read(url)
        } catch {
            NSLog("Finger session file unreadable, skipped: %@ (%@)", url.lastPathComponent, String(describing: error))
            return nil
        }
    }

    /// The saved-for-later checkpoint, or `nil` when it cannot be read. An unreadable one is
    /// moved aside under a new name, never overwritten or deleted, so it stops blocking every
    /// later session while its data stays on the device.
    private func readableCheckpoint() -> FingerSessionSummary? {
        if let summary = readOrLog(checkpointURL) {
            return summary
        }

        let stamp = Int(Date().timeIntervalSince1970)
        let aside = folder.appendingPathComponent("active-unreadable-\(stamp)-\(checkpointName)")
        try? FileManager.default.moveItem(at: checkpointURL, to: aside)
        return nil
    }

    private func save(_ summary: FingerSessionSummary, to url: URL) throws {
        try AtomicJSONFiles.write(FingerSessionRecord(summary), to: url)
    }
}
