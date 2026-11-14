//
//  BodyAngleHistoryViewModel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation
import Observation

/// Arm raise and elbow bend angles from saved therapy sessions, for the Progres tab.
@MainActor
@Observable
final class BodyAngleHistoryViewModel {
    struct Entry: Identifiable {
        let id: UUID
        let kind: TherapyKind
        let side: TherapySide
        let angle: BodyAngleResult
    }

    struct Session: Identifiable {
        let id: UUID
        let date: Date
        let entries: [Entry]
    }

    /// Newest first; only sessions with at least one recorded angle.
    private(set) var sessions: [Session] = []
    private(set) var failed = false
    @ObservationIgnored private let repository: any SessionRepository

    init(repository: any SessionRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            sessions = try await repository.history().compactMap(Self.session)
            failed = false
        } catch {
            failed = true
        }
    }

    /// Each activity's ranges are cumulative over its sets, so its last result holds them all.
    private static func session(_ summary: SessionSummary) -> Session? {
        let entries = summary.routine.activities.compactMap { activity -> Entry? in
            guard let angle = summary.results
                .last(where: { $0.activity.id == activity.id && $0.angles?.isEmpty == false })?
                .angles?.first else {
                return nil
            }

            return Entry(id: activity.id, kind: activity.kind, side: activity.side, angle: angle)
        }

        guard !entries.isEmpty else {
            return nil
        }

        return Session(id: summary.id, date: summary.startedAt, entries: entries)
    }
}
