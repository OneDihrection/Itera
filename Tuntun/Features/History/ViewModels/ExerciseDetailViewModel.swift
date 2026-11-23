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
    let clipURL: URL?
    /// Joint indices of the moving limb, in the skeleton drawn for the repetition.
    let emphasizedJoints: Set<Int>

    var recordsHand: Bool {
        rep.frames.contains { $0.hand != nil }
    }
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
    /// The day's best recorded repetition, drawn over the baseline's.
    var currentPeakRep: RecordedRep? { get }
    var baselinePeakRep: RecordedRep? { get }
    /// The day's first, hardest or last key repetition for the practice record; nil when the
    /// day recorded none.
    func keyRep(for role: KeyRepRole) -> RecordedRep?
    /// The day's recorded repetitions span more than one set, so a repetition names its set.
    var recordsSeveralSets: Bool { get }
    func load() async
    func close()
}

/// The floating detail panel for one exercise on one day: the day's figures, its best
/// repetition against an earlier session, and its first, hardest or last repetition's recording.
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

    @ObservationIgnored private let exercise: PracticedExercise
    @ObservationIgnored private let sessions: any SessionRepository
    @ObservationIgnored private let fingers: FingerHomeViewModel
    @ObservationIgnored private let fingerReplayRepository: any FingerSessionRepository
    @ObservationIgnored private let router: any HistoryRouterProtocol

    init(
        route: ExerciseDetailRoute,
        sessions: any SessionRepository,
        fingers: FingerHomeViewModel,
        fingerReplayRepository: any FingerSessionRepository,
        router: any HistoryRouterProtocol
    ) {
        day = route.day
        exercise = route.exercise
        self.sessions = sessions
        self.fingers = fingers
        self.fingerReplayRepository = fingerReplayRepository
        self.router = router
    }

    var exerciseID: String {
        exercise.id
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

    var currentPeakRep: RecordedRep? {
        guard let progress else {
            return nil
        }

        return peakRep(in: progress.sessionsOnDay.flatMap(reps(of:)), measure: progress.measure)
    }

    var baselinePeakRep: RecordedRep? {
        guard let progress, let baselineSession else {
            return nil
        }

        return peakRep(in: reps(of: baselineSession), measure: progress.measure)
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
        progress = ExerciseProgress(sessions: sessionHistory, day: day)
    }

    // MARK: - Sessions

    /// Guided and Balancing sessions that practised the exercise, with every set joined.
    private func guidedSessions() async throws -> [ExerciseSession] {
        try await sessions.history().compactMap { summary in
            let results = summary.results.filter { result in
                result.activity.kind.rawValue == exercise.id
                    && (result.outcome == .completed || result.completedWork > 0)
            }

            guard !results.isEmpty else {
                return nil
            }

            return ExerciseSession(
                date: summary.startedAt,
                report: .session(summary.id),
                side: Self.side(of: results),
                repetitions: results.reduce(0) { $0 + $1.completedWork },
                activeSeconds: results.reduce(0) { $0 + $1.practiceSeconds },
                metrics: results.flatMap { $0.repMetrics ?? [] }
            )
        }
    }

    private func fingerSessions() -> [ExerciseSession] {
        fingers.history
            .filter { $0.outcome != .savedForLater }
            .compactMap { summary in
                let results = summary.results.filter { result in
                    result.kind.rawValue == exercise.id
                        && (result.repetitions > 0 || result.activeSeconds > 0)
                }

                guard !results.isEmpty else {
                    return nil
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
            .filter { $0.activity.kind.rawValue == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }
            .flatMap { set in
                set.reps
                    .sorted { $0.metrics.repNumber < $1.metrics.repNumber }
                    .map { rep in
                        RecordedRep(
                            rep: rep,
                            setNumber: set.setNumber,
                            clipURL: clips[set.executionID]?[rep.metrics.repNumber],
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
            .filter { $0.exercise.rawValue == exercise.id }
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
                            clipURL: clips[key],
                            emphasizedJoints: HandSkeleton.emphasis(for: set.exercise)
                        )
                    }
            }
    }

    private func reps(of session: ExerciseSession) -> [RecordedRep] {
        recordedReps[session.report] ?? []
    }

    /// The repetition that reached furthest; the last one when the exercise has no measure.
    private func peakRep(in reps: [RecordedRep], measure: ExerciseMeasure) -> RecordedRep? {
        guard measure != .none else {
            return reps.last
        }

        return reps.max { first, second in
            (Self.peak(of: first.rep.metrics, measure: measure) ?? -.infinity)
                < (Self.peak(of: second.rep.metrics, measure: measure) ?? -.infinity)
        }
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
