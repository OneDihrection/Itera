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
    func recoverInterrupted() async throws
    func checkpoint(_ value: SessionCheckpoint) async throws
    func finalize(_ value: SessionSummary) async throws
}
