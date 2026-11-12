//
//  SessionReportViewModel.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import Foundation
import Observation

/// Loads one session's arm-movement results with their key-repetition replays, and words the
/// plain-language comparisons a clinician reads first.
@MainActor
@Observable
final class SessionReportViewModel {
    /// Changes smaller than these read as steady, given 2D camera noise.
    private static let durationChangeSeconds = 0.5
    private static let peakChangeDegrees = 5.0
    /// Below this share of usable frames a replay is flagged as unclear rather than shown with a
    /// percentage, so a reader is warned only when it matters.
    private static let lowTrackingCoverage = 0.7

    /// The hardest repetition is the one most worth a clinician's first look.
    let defaultRole = KeyRepRole.hardest

    let sessionID: UUID
    private(set) var summary: SessionSummary?
    private(set) var loading = false
    private(set) var errorKey: String?
    /// The replay file exists but could not be read; the metrics are still shown.
    private(set) var replaysUnavailable = false
    private var keyReps: [ActivityKeyReps] = []
    /// Privacy-filtered clips by set execution and repetition number.
    private var clipURLs: [UUID: [Int: URL]] = [:]
    @ObservationIgnored private let repository: any SessionRepository

    init(sessionID: UUID, repository: any SessionRepository) {
        self.sessionID = sessionID
        self.repository = repository
    }

    var results: [SessionActivityResult] {
        summary?.results.filter { $0.activity.kind.recordsMovement } ?? []
    }

    func load() async {
        guard !loading else {
            return
        }

        loading = true
        defer { loading = false }

        do {
            summary = try await repository.history().first { $0.id == sessionID }
            errorKey = summary == nil ? "history.report.missing" : nil
        } catch {
            errorKey = "towel.historyError"
            return
        }

        do {
            keyReps = try await repository.keyReps(sessionID: sessionID)
            replaysUnavailable = false
        } catch {
            keyReps = []
            replaysUnavailable = true
        }

        clipURLs = await repository.repClipURLs(sessionID: sessionID)
    }

    // MARK: - Set summary

    /// The single most important sentence for a set, shown on its headline card: the peak-angle
    /// change when there is one, otherwise the change in pace.
    func headline(for result: SessionActivityResult) -> LocalizedStringResource? {
        notes(for: result).last
    }

    func averageDuration(for result: SessionActivityResult) -> Double? {
        guard let metrics = result.repMetrics, !metrics.isEmpty else {
            return nil
        }

        return metrics.reduce(0) { $0 + $1.duration } / Double(metrics.count)
    }

    /// Sit-to-stand measures the knee straightening; every other angle is the movement itself.
    func peakTitleKey(for result: SessionActivityResult) -> String {
        result.activity.kind == .sitToStand ? "history.report.kneeExtension" : "history.report.highestPeak"
    }

    func highestPeak(for result: SessionActivityResult) -> Double? {
        result.repMetrics?.compactMap(\.peakAngle).max()
    }

    /// The saved clip of `rep`, when one was recorded.
    func clipURL(for rep: KeyRep, in result: SessionActivityResult) -> URL? {
        clipURLs[result.executionID]?[rep.metrics.repNumber]
    }

    func isTrackingLow(_ rep: KeyRep) -> Bool {
        rep.metrics.trackingCoverage < Self.lowTrackingCoverage
    }

    /// The repetition holding `role`, falling back to the first recorded one.
    func keyRep(_ role: KeyRepRole, for result: SessionActivityResult) -> KeyRep? {
        let reps = keyReps(for: result)
        return reps.first { $0.roles.contains(role) } ?? reps.first
    }

    /// Deletes the session and its replays; returns whether it succeeded.
    func delete() async -> Bool {
        do {
            try await repository.delete(id: sessionID)
            return true
        } catch {
            errorKey = "towel.deleteError"
            return false
        }
    }

    // MARK: - Repetitions

    func keyReps(for result: SessionActivityResult) -> [KeyRep] {
        let reps = keyReps.first { $0.executionID == result.executionID }?.reps ?? []
        return reps.sorted { $0.metrics.repNumber < $1.metrics.repNumber }
    }

    /// Comparisons between the first and last repetition of a set; empty with fewer than two.
    func notes(for result: SessionActivityResult) -> [LocalizedStringResource] {
        guard let metrics = result.repMetrics,
              metrics.count > 1,
              let first = metrics.first,
              let last = metrics.last
        else {
            return []
        }

        var notes: [LocalizedStringResource] = [durationNote(first: first, last: last)]

        if let firstPeak = first.peakAngle, let lastPeak = last.peakAngle {
            let change = Int((lastPeak - firstPeak).rounded())

            if Double(change) <= -Self.peakChangeDegrees {
                notes.append("history.note.peakDropped \(-change)")
            } else if Double(change) >= Self.peakChangeDegrees {
                notes.append("history.note.peakRose \(change)")
            }
        }

        return notes
    }

    private func durationNote(first: RepMetrics, last: RepMetrics) -> LocalizedStringResource {
        let change = last.duration - first.duration
        let seconds = abs(change).formatted(.number.precision(.fractionLength(1)))

        if change >= Self.durationChangeSeconds {
            return "history.note.slower \(seconds)"
        }

        if change <= -Self.durationChangeSeconds {
            return "history.note.faster \(seconds)"
        }

        return "history.note.steadyPace"
    }
}
