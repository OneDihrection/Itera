//
//  ExerciseDetailViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 23/11/2026.
//

import Foundation
import Observation

/// One recorded key repetition, ready to draw: its skeleton, its clip when one was saved and the
/// joints of the moving limb.
struct RecordedRep: Equatable {
    let rep: KeyRep
    /// The set the repetition belongs to, within its session.
    let setNumber: Int
    /// The saved clip; nil when none was recorded or it was deleted.
    var clip: RepClip?
    /// Joint indices of the moving limb, in the skeleton drawn for the repetition.
    let emphasizedJoints: Set<Int>

    var clipURL: URL? {
        clip?.url
    }

    var recordsHand: Bool {
        rep.frames.contains { $0.hand != nil }
    }
}

/// One saved key-repetition clip and where its repository keeps it.
struct RepClip: Equatable {
    enum Reference: Equatable {
        case session(id: UUID, executionID: UUID, repNumber: Int)
        case finger(id: UUID, key: FingerRepClipKey)
    }

    let url: URL
    let reference: Reference
}

@MainActor
protocol ExerciseDetailViewModelProtocol: AnyObject, Observable {
    /// The exercise's raw value, the same ID the daily plan uses.
    var exerciseID: String { get }
    var titleKey: String { get }
    /// The side every session of the day practised, named in the title; nil when they differ.
    var titleSide: TherapySide? { get }
    /// Start of the day shown.
    var day: Date { get }
    var loading: Bool { get }
    var errorKey: String? { get }
    /// Nil until history is read.
    var progress: ExerciseProgress? { get }
    var baseline: ProgressBaseline { get set }
    /// The session `baseline` names; nil when the exercise was not practised then.
    var baselineSession: ExerciseSession? { get }
    /// The day's first, hardest or last key repetition; nil when the day recorded none. The
    /// practice record shows only the hardest; first and last are still recorded.
    func keyRep(for role: KeyRepRole) -> RecordedRep?
    /// The day's recorded repetitions span more than one set, so a repetition names its set.
    var recordsSeveralSets: Bool { get }
    /// Set when the last clip deletion failed.
    var clipDeleteErrorKey: String? { get }
    func load() async
    /// Deletes the repetition's clip, keeping its skeleton and figures.
    func deleteClip(of rep: RecordedRep) async
    /// True while the day's record is being deleted.
    var deletingRecord: Bool { get }
    /// Set when deleting the day's record failed.
    var recordDeleteErrorKey: String? { get }
    /// A session of the day also holds other exercises, which deleting the record removes too.
    var recordSharesSessions: Bool { get }
    /// Deletes the shown session (every session of the day for a plan-only entry) with its
    /// replays and clips, and the plan's done mark once no session of the exercise is left that
    /// day, then closes the panel.
    func deleteRecord() async
    func close()
}

/// The floating detail panel for one session of an exercise on one day (every session of the
/// day for an entry only the plan recorded): its figures, its best repetition against an
/// earlier session, and its hardest repetition's recording.
///
/// It reads the guided session history once, takes finger history from `FingerHomeViewModel`
/// (already loaded by the Progress tab), and reads key repetitions only for the day's sessions
/// and the chosen baseline session.
@MainActor
@Observable
final class ExerciseDetailViewModel: ExerciseDetailViewModelProtocol {
    let day: Date
    private(set) var loading = false
    private(set) var errorKey: String?
    private(set) var clipDeleteErrorKey: String?
    private(set) var deletingRecord = false
    private(set) var recordDeleteErrorKey: String?
    private(set) var progress: ExerciseProgress?

    var baseline: ProgressBaseline = .firstSession {
        didSet {
            guard baseline != oldValue else {
                return
            }

            Task {
                await loadBaselineReps()
            }
        }
    }

    /// Every session of the exercise, kept so finger metrics can be filled in as they arrive.
    private var sessionHistory: [ExerciseSession] = []
    /// Recorded key repetitions of this exercise, by session.
    private var recordedReps: [PracticedExercise.Report: [RecordedRep]] = [:]
    /// Sessions that also practised another exercise.
    private var sharedReports: Set<PracticedExercise.Report> = []

    @ObservationIgnored private let exercise: PracticedExercise
    @ObservationIgnored private let sessions: any SessionRepository
    @ObservationIgnored private let fingers: FingerHomeViewModel
    @ObservationIgnored private let fingerReplayRepository: any FingerSessionRepository
    @ObservationIgnored private let planHistoryRepository: any DailyPlanHistoryRepository
    @ObservationIgnored private let history: any PracticeHistoryProviding
    @ObservationIgnored private let router: any HistoryRouterProtocol

    init(
        route: ExerciseDetailRoute,
        sessions: any SessionRepository,
        fingers: FingerHomeViewModel,
        fingerReplayRepository: any FingerSessionRepository,
        planHistoryRepository: any DailyPlanHistoryRepository,
        history: any PracticeHistoryProviding,
        router: any HistoryRouterProtocol
    ) {
        day = route.day
        exercise = route.exercise
        self.sessions = sessions
        self.fingers = fingers
        self.fingerReplayRepository = fingerReplayRepository
        self.planHistoryRepository = planHistoryRepository
        self.history = history
        self.router = router
    }

    var exerciseID: String {
        exercise.exerciseID
    }

    var titleKey: String {
        exercise.titleKey
    }

    var titleSide: TherapySide? {
        progress?.side
    }

    var baselineSession: ExerciseSession? {
        progress?.baselineSession(baseline)
    }

    /// Day-level key repetitions, over the day's recorded reps in practice order (sessions oldest
    /// first, then sets, then repetitions). First and last are the earliest and latest reps
    /// holding that role; the hardest is, across sets, the one that reached least, then the
    /// longest. Each falls back to every rep when none holds its role.
    func keyRep(for role: KeyRepRole) -> RecordedRep? {
        guard let progress else {
            return nil
        }

        let reps = progress.sessionsOnDay.flatMap(reps(of:))
        let holding = reps.filter { $0.rep.roles.contains(role) }
        let candidates = holding.isEmpty ? reps : holding

        switch role {
        case .first:
            return candidates.first
        case .last:
            return candidates.last
        case .hardest:
            return hardest(in: candidates, measure: progress.measure)
        }
    }

    var recordSharesSessions: Bool {
        progress?.sessionsOnDay.contains { sharedReports.contains($0.report) } ?? false
    }

    var recordsSeveralSets: Bool {
        guard let progress else {
            return false
        }

        let sets = progress.sessionsOnDay.flatMap { session in
            reps(of: session).map { "\(session.date.timeIntervalSinceReferenceDate)-\($0.setNumber)" }
        }

        return Set(sets).count > 1
    }

    private func hardest(in reps: [RecordedRep], measure: ExerciseMeasure) -> RecordedRep? {
        reps.min { first, second in
            let firstPeak = Self.peak(of: first.rep.metrics, measure: measure) ?? 0
            let secondPeak = Self.peak(of: second.rep.metrics, measure: measure) ?? 0

            if firstPeak != secondPeak {
                return firstPeak < secondPeak
            }

            return first.rep.metrics.duration > second.rep.metrics.duration
        }
    }

    // MARK: - Loading

    func load() async {
        guard !loading, progress == nil else {
            return
        }

        loading = true
        defer { loading = false }

        do {
            sessionHistory = try await guidedSessions() + fingerSessions()
            errorKey = nil
        } catch {
            errorKey = "towel.historyError"
            return
        }

        rebuildProgress()

        for session in progress?.sessionsOnDay ?? [] {
            await loadReps(of: session)
        }

        // Finger summaries keep no per-repetition values, so the trend reads their repetitions.
        let trendSessions = progress?.recentEarlierSessions(limit: ExerciseProgress.trendLimit) ?? []

        for session in trendSessions where !session.keepsEveryRepetition {
            await loadReps(of: session)
        }

        await loadBaselineReps()
    }

    func close() {
        router.dismissExerciseDetail()
    }

    // MARK: - Deleting the day's record

    func deleteRecord() async {
        guard !deletingRecord, let progress else {
            return
        }

        deletingRecord = true
        recordDeleteErrorKey = nil
        defer { deletingRecord = false }

        let deleted = await deleteSessions(progress.sessionsOnDay)

        if !keepsOtherSessionsOnDay(after: progress.sessionsOnDay) {
            await removePlanMark()
        }

        // Refreshes even after a partial failure, so the calendar and day page show what is left.
        await history.refresh()

        guard deleted else {
            recordDeleteErrorKey = "exerciseDetail.deleteRecord.error"
            return
        }

        router.dismissExerciseDetail()
    }

    /// Another session of the exercise is left on the day, so the plan's done mark stays with it.
    private func keepsOtherSessionsOnDay(after deletedSessions: [ExerciseSession]) -> Bool {
        let deletedReports = Set(deletedSessions.map(\.report))

        return sessionHistory.contains { session in
            !deletedReports.contains(session.report)
                && Calendar.current.isDate(session.date, inSameDayAs: day)
        }
    }

    /// The plan's mark would otherwise keep the exercise on the day; a failure here leaves the
    /// sessions deleted and is only logged.
    private func removePlanMark() async {
        do {
            try await planHistoryRepository.removeCompleted(exercise.exerciseID, on: day)
        } catch {
            LogManager.shared.error("Plan mark not removed after deleting a record", error: error, category: .storage)
        }
    }

    /// Deletes each session with its replays and clips; false when any deletion failed.
    private func deleteSessions(_ sessionsToDelete: [ExerciseSession]) async -> Bool {
        var deletedAll = true

        for session in sessionsToDelete {
            do {
                switch session.report {
                case .session(let id):
                    try await sessions.delete(id: id)
                case .finger(let id):
                    try await fingerReplayRepository.delete(id)
                }
            } catch {
                deletedAll = false
                LogManager.shared.error("Exercise session not deleted", error: error, category: .storage)
            }
        }

        return deletedAll
    }

    // MARK: - Deleting clips

    func deleteClip(of rep: RecordedRep) async {
        guard let clip = rep.clip else {
            return
        }

        clipDeleteErrorKey = nil

        do {
            switch clip.reference {
            case .session(let id, let executionID, let repNumber):
                try await sessions.deleteRepClip(
                    sessionID: id,
                    executionID: executionID,
                    repNumber: repNumber
                )
            case .finger(let id, let key):
                try await fingerReplayRepository.deleteRepClip(sessionID: id, key: key)
            }
        } catch {
            clipDeleteErrorKey = "exerciseDetail.record.deleteClip.error"
            LogManager.shared.error("Key-repetition clip not deleted", error: error, category: .storage)
            return
        }

        removeClip(clip)
    }

    /// Drops the deleted clip from the loaded repetitions, so the record shows the skeleton.
    private func removeClip(_ clip: RepClip) {
        for (report, reps) in recordedReps {
            guard reps.contains(where: { $0.clip == clip }) else {
                continue
            }

            recordedReps[report] = reps.map { candidate in
                guard candidate.clip == clip else {
                    return candidate
                }

                var cleared = candidate
                cleared.clip = nil
                return cleared
            }
        }
    }

    private func loadBaselineReps() async {
        guard let baselineSession else {
            return
        }

        await loadReps(of: baselineSession)
    }

    /// Reads one session's key repetitions once. Finger sessions keep no per-repetition metrics
    /// in their summary, so theirs come from these repetitions.
    private func loadReps(of session: ExerciseSession) async {
        guard recordedReps[session.report] == nil else {
            return
        }

        let reps: [RecordedRep]

        switch session.report {
        case .session(let id):
            reps = await guidedReps(sessionID: id)
        case .finger(let id):
            reps = await fingerReps(sessionID: id)
        }

        recordedReps[session.report] = reps

        guard !session.keepsEveryRepetition else {
            return
        }

        sessionHistory = sessionHistory.map { candidate in
            guard candidate.report == session.report else {
                return candidate
            }

            var filled = candidate
            filled.metrics = reps.map(\.rep.metrics)
            return filled
        }

        rebuildProgress()
    }

    private func rebuildProgress() {
        progress = ExerciseProgress(
            sessions: sessionHistory,
            day: day,
            focus: exercise.report
        )
    }

    // MARK: - Sessions

    /// Guided and Balancing sessions that practised the exercise, with every set joined.
    private func guidedSessions() async throws -> [ExerciseSession] {
        try await sessions.history().compactMap { summary in
            let practised = summary.results.filter { result in
                result.outcome == .completed || result.completedWork > 0
            }
            let results = practised.filter { $0.activity.kind.rawValue == exercise.exerciseID }

            guard !results.isEmpty else {
                return nil
            }

            if results.count < practised.count {
                sharedReports.insert(.session(summary.id))
            }

            return ExerciseSession(
                date: summary.startedAt,
                report: .session(summary.id),
                side: Self.side(of: results),
                repetitions: results.reduce(0) { $0 + $1.completedWork },
                activeSeconds: results.reduce(0) { $0 + Self.activeSeconds(of: $1) },
                metrics: results.flatMap { $0.repMetrics ?? [] }
            )
        }
    }

    /// A set's practice time. Movement, fold towel and Balancing sets saved before they credited
    /// practice time stored 0; their repetition durations stand in for it.
    private static func activeSeconds(of result: SessionActivityResult) -> Double {
        guard result.practiceSeconds <= 0 else {
            return result.practiceSeconds
        }

        return (result.repMetrics ?? []).reduce(0) { $0 + $1.duration }
    }

    private func fingerSessions() -> [ExerciseSession] {
        fingers.history
            .filter { $0.outcome != .savedForLater }
            .compactMap { summary in
                let practised = summary.results.filter { result in
                    result.repetitions > 0 || result.activeSeconds > 0
                }
                let results = practised.filter { $0.kind.rawValue == exercise.exerciseID }

                guard !results.isEmpty else {
                    return nil
                }

                if results.count < practised.count {
                    sharedReports.insert(.finger(summary.id))
                }

                return ExerciseSession(
                    date: summary.started,
                    report: .finger(summary.id),
                    side: summary.routine.side == .left ? .left : .right,
                    repetitions: results.reduce(0) { $0 + $1.repetitions },
                    activeSeconds: results.reduce(0) { $0 + $1.activeSeconds },
                    metrics: []
                )
            }
    }

    /// The one side every set practised; nil when sides alternated or differed between sets.
    private static func side(of results: [SessionActivityResult]) -> TherapySide? {
        let sides = Set(
            results.map { result -> TherapySide? in
                guard result.activity.hasSide, !result.activity.alternatesSides else {
                    return nil
                }

                return result.activity.side
            }
        )

        guard sides.count == 1 else {
            return nil
        }

        return sides.first ?? nil
    }

    // MARK: - Key repetitions

    /// A session whose replay file cannot be read simply has no recording to show.
    private func guidedReps(sessionID: UUID) async -> [RecordedRep] {
        let sets = (try? await sessions.keyReps(sessionID: sessionID)) ?? []
        let clips = await sessions.repClipURLs(sessionID: sessionID)

        return sets
            .filter { $0.activity.kind.rawValue == exercise.exerciseID }
            .sorted { $0.setNumber < $1.setNumber }
            .flatMap { set in
                set.reps
                    .sorted { $0.metrics.repNumber < $1.metrics.repNumber }
                    .map { rep in
                        let repNumber = rep.metrics.repNumber
                        let clip = clips[set.executionID]?[repNumber].map { url in
                            RepClip(
                                url: url,
                                reference: .session(
                                    id: sessionID,
                                    executionID: set.executionID,
                                    repNumber: repNumber
                                )
                            )
                        }

                        return RecordedRep(
                            rep: rep,
                            setNumber: set.setNumber,
                            clip: clip,
                            emphasizedJoints: set.activity.kind == .foldTowel
                                ? HandSkeleton.towelEmphasis
                                : BodyJoint.movingChain(for: set.activity, side: rep.metrics.side)
                        )
                    }
            }
    }

    private func fingerReps(sessionID: UUID) async -> [RecordedRep] {
        let sets = (try? await fingerReplayRepository.keyReps(sessionID: sessionID)) ?? []
        let clips = await fingerReplayRepository.repClipURLs(sessionID: sessionID)

        return sets
            .filter { $0.exercise.rawValue == exercise.exerciseID }
            .sorted { $0.setNumber < $1.setNumber }
            .flatMap { set in
                set.reps
                    .sorted { $0.metrics.repNumber < $1.metrics.repNumber }
                    .map { rep in
                        let key = FingerRepClipKey(
                            exercise: set.exercise,
                            setNumber: set.setNumber,
                            repNumber: rep.metrics.repNumber
                        )

                        return RecordedRep(
                            rep: rep,
                            setNumber: set.setNumber,
                            clip: clips[key].map { url in
                                RepClip(url: url, reference: .finger(id: sessionID, key: key))
                            },
                            emphasizedJoints: HandSkeleton.emphasis(for: set.exercise)
                        )
                    }
            }
    }

    private func reps(of session: ExerciseSession) -> [RecordedRep] {
        recordedReps[session.report] ?? []
    }

    static func peak(of metrics: RepMetrics, measure: ExerciseMeasure) -> Double? {
        switch measure {
        case .angle:
            return metrics.peakAngle
        case .range:
            return metrics.peakFraction
        case .none:
            return nil
        }
    }
}
