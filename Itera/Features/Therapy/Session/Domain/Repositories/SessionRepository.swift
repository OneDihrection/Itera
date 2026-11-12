//
//  SessionRepository.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

struct SessionCheckpoint: Codable {
    let id: UUID
    let routine: Routine
    let startedAt: Date
    let results: [SessionActivityResult]
}

protocol SessionRepository: Sendable {
    func history() async throws -> [SessionSummary]
    /// How many saved summaries the last `history()` call skipped because they could not be read.
    func unreadableHistoryCount() async -> Int
    func delete(id: UUID) async throws
    func recoverInterrupted() async throws
    func checkpoint(_ value: SessionCheckpoint) async throws
    func finalize(_ value: SessionSummary) async throws
    /// Saves one set's key repetitions beside the session's summary, replacing an earlier save
    /// of the same set.
    func saveKeyReps(_ value: ActivityKeyReps, sessionID: UUID) async throws
    /// Every set's key repetitions for a session; empty when none were recorded.
    func keyReps(sessionID: UUID) async throws -> [ActivityKeyReps]
    /// Saves the privacy-filtered clips of one set's key repetitions, keyed by repetition number.
    func saveRepClips(_ clips: [Int: [RepClipFrame]], for keyReps: ActivityKeyReps, sessionID: UUID) async throws
    /// Saved clip files by set execution identity and repetition number; empty when none exist.
    func repClipURLs(sessionID: UUID) async -> [UUID: [Int: URL]]
}
