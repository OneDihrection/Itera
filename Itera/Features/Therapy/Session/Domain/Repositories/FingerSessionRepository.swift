//
//  FingerSessionRepository.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

protocol FingerHistoryReading: Sendable {
    func history() async throws -> [FingerSessionSummary]
}

protocol FingerSessionRepository: FingerHistoryReading {
    func checkpoint(_ summary: FingerSessionSummary) async throws
    func pending() async throws -> FingerSessionSummary?
    func finalize(_ summary: FingerSessionSummary) async throws
    func delete(_ id: UUID) async throws
    func deleteHistory() async throws
    /// Saves one set's key-repetition hand skeletons beside the session, replacing an earlier
    /// save of the same exercise and set.
    func saveKeyReps(_ value: FingerKeyReps, sessionID: UUID) async throws
    /// Every set's key repetitions for a session; empty when none were recorded.
    func keyReps(sessionID: UUID) async throws -> [FingerKeyReps]
    /// Saves the clips of one set's key repetitions, keyed by repetition number.
    func saveRepClips(_ clips: [Int: [RepClipFrame]], for keyReps: FingerKeyReps, sessionID: UUID) async throws
    /// Saved clip files by exercise, set number and repetition number; empty when none exist.
    func repClipURLs(sessionID: UUID) async -> [FingerRepClipKey: URL]
}

/// Identifies one saved finger clip.
struct FingerRepClipKey: Hashable {
    let exercise: FingerExercise
    let setNumber: Int
    let repNumber: Int
}
