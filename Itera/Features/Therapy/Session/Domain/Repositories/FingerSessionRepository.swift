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
}
