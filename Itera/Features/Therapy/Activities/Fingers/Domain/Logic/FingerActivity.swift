//
//  FingerActivity.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//
import Foundation

enum FingerPhase: Equatable {
    case baseline, target, range, rangeResult, demonstration, countdown, active, feedback, rest, finished
}

struct FingerActivity {
    let kind: FingerExercise
    let routine: FingerRoutine
    let restAfterFinalSet: Bool
    private(set) var phase: FingerPhase = .baseline
    private(set) var set = 1
    private(set) var repetitions = 0
    private(set) var totalRepetitions = 0
    private(set) var completedSets = 0
    private(set) var finger = 0
    private(set) var returning = false
    private(set) var progress = 0.0
    private(set) var movementFraction = 0.0
    private(set) var remaining = 0.0
    private(set) var activeSeconds = 0.0
    private(set) var baselines = [Double](repeating: 0, count: 4)
    private(set) var targets = [Double](repeating: 0, count: 4)
    private(set) var best = [Double](repeating: 0, count: 4)
    private(set) var holdCompletionID: UUID?
    private var holdCompletionWasPresented = false
    /// Credited hold time; survives brief tracking loss and zone wobble without crediting them.
    private var hold = InterruptibleHold()
    private var holdValue = 0.0
    private var holdSum = 0.0
    private var holdCount = 0
    private var lastTimestamp: Double?
    private var lastTick: Double?
    private var narrationFinished = false
    private var awaitingStart = true
    private var peakStart: Double?
    private var peakValue = 0.0
    private var peakSum = 0.0
    private var peakCount = 0
    private var initialized = [Bool](repeating: false, count: 4)
    private(set) var rangeElapsed = 0.0
    private(set) var rangeTooSmall = false
    /// The patient held the start position through the ready countdown, so sweeping can begin.
    private(set) var rangeReady = false
    private var rangeLow: Double?
    private var rangeHigh: Double?
    private var rangeCandidate: Double?
    private var rangeCandidateStart = 0.0
    private var rangeCandidateSum = 0.0
    private var rangeCandidateCount = 0
    /// Sweep time at which the measured range last grew, so a settled range can finish early.
    private var rangeGrowthElapsed = 0.0
    /// Smooths the scored metric for every exercise; restarted whenever evidence is lost.
    private var metricFilter = FingerMetricFilter()
    /// Forearm rotation only: +1 or -1, the sign the patient's turn produces. It is learned while
    /// the target pose is calibrated and then fixed for the exercise.
    private var forearmDirection = 1.0
    private var forearmDirectionLocked = false
    /// Change from the start pose that shows which way the patient turns.
    private static let forearmTurnThreshold = 0.08

    init(kind: FingerExercise, routine: FingerRoutine, restAfterFinalSet: Bool = true) {
        self.kind = kind
        self.routine = routine
        self.restAfterFinalSet = restAfterFinalSet
        phase = kind.calibratesRange ? .range : .baseline
    }





    /// Usable seconds the patient sweeps the movement while the range is measured.
    static let rangeDuration = 10.0
    /// How long the start position is held, as a visible countdown, before the sweep is measured.
    static let readyCountdown = 3.0
    /// Narrowest sweep, in metric units, that still gives the repetitions a usable target.
    static let minimumRange = 0.15
    /// A stable pose must stay this close for this long to count toward the range.
    private static let rangeTolerance = 0.07
    private static let rangeStableSeconds = 0.2
    /// The sweep may end early once the range is wide enough and has stopped growing.
    private static let rangeMinimumSweepSeconds = 4.0
    private static let rangeSettleSeconds = 3.0
    private static let rangeGrowthStep = 0.03
    /// Smallest change from the start pose that counts as reaching the target pose. Smaller
    /// changes are detector noise or a half movement, so their hold timer never runs.
    private static let minimumTargetChange = 0.15
    /// Thumb-to-fingertip distance, as a fraction of palm length, that counts as touching.
    /// A hold starts only at `contactEntry` and survives up to `contactExit`.
    private static let contactEntry = 0.35
    private static let contactExit = 0.45

    var rangeProgress: Double { min(1, rangeElapsed / Self.rangeDuration) }
    /// How far the automatic start of practice has advanced after the range is shown.

    var needsStart: Bool { awaitingStart }
    var holdDuration: Double { phase == .range ? Self.readyCountdown : 2 }
    var isHolding: Bool { hold.isHolding || holdCompletionID != nil }
    /// A completed hold presents a full timer until its completion is acknowledged.
    var holdElapsed: Double {
        holdCompletionID != nil ? holdDuration : min(holdDuration, hold.elapsed)
    }
    var holdRemaining: Double { max(0, holdDuration - holdElapsed) }
    var calibrationCount: Int { kind.isSequential ? 4 : 1 }
    var observedGain: Double? {
        let changes = (0..<calibrationCount).filter { initialized[$0] }.map {
            max(0, best[$0] - targets[$0]) / max(0.08, targets[$0] - baselines[$0])
        }
        return changes.isEmpty ? nil : changes.max()
    }

    mutating func restore(_ result: FingerExerciseResult) {
        completedSets = result.completedSets
        totalRepetitions = result.repetitions
        repetitions = result.repetitions % routine.repetitions
        set = min(routine.sets, completedSets + 1)
        activeSeconds = result.activeSeconds
    }

    /// Brief evidence loss (a bystander, an occluded hand) freezes the current hold.
    ///
    /// The partial hold survives for `InterruptibleHold.trackingGrace` without receiving
    /// credit for the missing time; longer losses go through `breakEvidence()` instead.
    mutating func suspendEvidence(at now: Double) {
        // An earned endpoint may finish its visual acknowledgment during a brief occlusion.
        if holdCompletionID == nil, !hold.interrupt(at: now, grace: InterruptibleHold.trackingGrace) {
            resetHold()
        }

        peakStart = nil
        lastTimestamp = nil
        metricFilter.reset()
    }

    mutating func breakEvidence() {
        resetHold()
        metricFilter.reset()
        peakStart = nil
        rangeCandidate = nil
        awaitingStart = true
        lastTimestamp = nil
        progress = 0
        returning = false
    }

    mutating func suspendClock() {
        lastTick = nil
    }

    mutating func recalibrate() {
        suspendClock()
        phase = kind.calibratesRange ? .range : .baseline
        finger = 0
        initialized = [Bool](repeating: false, count: 4)
        forearmDirection = 1
        forearmDirectionLocked = false
        resetRange()
        rangeTooSmall = false
        breakEvidence()
    }

    /// Ends the rest early. The next set still begins with its countdown, and the next
    /// exercise still begins with its own setup; only the waiting time is shortened.
    mutating func skipRest() {
        guard phase == .rest else {
            return
        }

        remaining = 0
    }

    mutating func remeasureRange() {
        guard phase == .rangeResult else {
            return
        }
        initialized[0] = false
        rangeTooSmall = false
        resetRange()
        phase = .range
    }

    mutating func guidanceStarted() {
        narrationFinished = false
    }

    mutating func guidanceCompleted() {
        narrationFinished = true
    }

    mutating func tick(_ now: Double, ready: Bool) {
        guard ready else {
            suspendClock()
            return
        }
        defer { lastTick = now }
        if holdCompletionID != nil {
            if holdCompletionWasPresented && narrationFinished {
                commitCompletedHold()
            }
            return
        }
        let delta = min(0.2, max(0, now - (lastTick ?? now)))
        switch phase {
        case .demonstration, .rangeResult:
            if narrationFinished {
                beginCountdown()
            }
        case .feedback:
            guard narrationFinished else {
                return
            }
            remaining -= delta
            if remaining <= 0 {
                if completedSets >= routine.sets && !restAfterFinalSet {
                    phase = .finished
                } else {
                    phase = .rest
                    remaining = Double(routine.restSeconds)
                }
            }
        case .countdown:
            remaining -= delta
            if remaining <= 0 {
                phase = .active
            }
        case .rest:
            remaining -= delta
            if remaining <= 0 {
                if completedSets >= routine.sets {
                    phase = .finished
                } else {
                    set += 1
                    repetitions = 0
                    awaitingStart = true
                    beginCountdown()
                }
            }
        default:
            break
        }
    }

    private mutating func beginCountdown() {
        phase = .countdown
        remaining = 3
        narrationFinished = false
    }

    mutating func observe(_ evidence: HandEvidence, now: Double) {
        guard now - evidence.timestamp >= 0, now - evidence.timestamp <= 0.3,
              evidence.timestamp > (lastTimestamp ?? -.infinity),
              let rawValue = evidence.metric(for: kind, finger: finger), rawValue.isFinite else {
            breakEvidence()
            return
        }
        let value = metricFilter.consume(rawValue, at: evidence.timestamp)
            * (kind == .forearmRotation ? forearmDirection : 1)
        // A completed hold remains the current instruction until its full ring is presented.
        if holdCompletionID != nil {
            lastTimestamp = evidence.timestamp
            return
        }
        let delta = evidence.timestamp - (lastTimestamp ?? evidence.timestamp)

        // A frame gap earns no hold credit; only a gap beyond the grace restarts the cycle.
        if delta > InterruptibleHold.maximumCreditedStep {
            peakStart = nil
        }

        if delta > InterruptibleHold.trackingGrace {
            resetHold()
            returning = false
            awaitingStart = true
        }
        lastTimestamp = evidence.timestamp
        // The sweep is measured while its instruction is still being read, so the patient can
        // start turning at once; every other stage waits for its narration.
        let measuresDuringNarration = phase == .range && rangeReady

        if !narrationFinished, !measuresDuringNarration, [.baseline, .target, .active, .range].contains(phase) {
            resetHold()
            return
        }
        switch phase {
        case .baseline, .target:
            capture(adoptingForearmDirection(value), time: evidence.timestamp)
        case .range:
            captureRange(value, time: evidence.timestamp, delta: delta)
        case .active:
            activeSeconds += delta <= 0.3 ? min(0.2, delta) : 0
            // Only stable observations contribute a peak; single-frame extremes do not.
            let range = targets[finger] - baselines[finger]
            guard range > 0.08 else {
                return
            }
            let normalized = (value - baselines[finger]) / range
            movementFraction = min(1, max(0, normalized))
            capturePeak(value, time: evidence.timestamp, tolerance: range * 0.12)
            if awaitingStart {
                guard normalized <= (hold.isHolding ? 0.30 : 0.25) else {
                    leaveZone(at: evidence.timestamp)
                    return
                }
                if stable(value, time: evidence.timestamp, tolerance: range * 0.20, duration: holdDuration) {
                    markHoldComplete()
                }
                return
            }
            progress = min(1, max(0, returning ? 1 - normalized : normalized))
            // Separate entry/exit bands prevent tiny boundary noise from restarting a valid hold.
            // They are narrow so a pose that slips away from the target stops the timer.
            let holding = hold.isHolding
            let arrived = returning
                ? normalized <= (holding ? 0.30 : 0.25)
                : normalized >= (holding ? 0.75 : 0.80) && touchesFingertip(value, holding: holding)
            guard arrived else {
                leaveZone(at: evidence.timestamp)
                return
            }
            guard stable(value, time: evidence.timestamp, tolerance: range * 0.20, duration: holdDuration) else {
                return
            }
            markHoldComplete()
        default:
            break
        }
    }

    private mutating func capturePeak(_ value: Double, time: Double, tolerance: Double) {
        if peakStart == nil || abs(value - peakValue) > tolerance {
            peakStart = time
            peakValue = value
            peakSum = 0
            peakCount = 0
        }
        peakSum += value
        peakCount += 1
        if time - (peakStart ?? time) >= 0.5 {
            best[finger] = max(best[finger], peakSum / Double(peakCount))
        }
    }

    /// Records the farthest stable poses reached while the patient sweeps the movement; a pose
    /// that is not held briefly cannot become an endpoint, so single-frame extremes are ignored.
    private mutating func captureRange(_ value: Double, time: Double, delta: Double) {
        // A countdown starts once the hand is held steady in the start position.
        guard rangeReady else {
            guard stable(value, time: time, tolerance: 0.10, duration: holdDuration) else {
                return
            }
            rangeReady = true
            resetHold()
            return
        }
        rangeElapsed += delta > 0 && delta <= 0.3 ? min(0.2, delta) : 0
        if let candidate = rangeCandidate, abs(value - candidate) <= Self.rangeTolerance {
            rangeCandidateSum += value
            rangeCandidateCount += 1
        } else {
            rangeCandidate = value
            rangeCandidateStart = time
            rangeCandidateSum = value
            rangeCandidateCount = 1
        }
        if time - rangeCandidateStart >= Self.rangeStableSeconds {
            let mean = rangeCandidateSum / Double(rangeCandidateCount)
            let previousLow = rangeLow
            let previousHigh = rangeHigh
            rangeLow = min(rangeLow ?? mean, mean)
            rangeHigh = max(rangeHigh ?? mean, mean)

            if rangeGrew(from: previousLow, and: previousHigh) {
                rangeGrowthElapsed = rangeElapsed
            }
        }
        progress = rangeProgress
        guard rangeElapsed >= Self.rangeDuration || rangeHasSettled else {
            return
        }
        guard let low = rangeLow, let high = rangeHigh, high - low >= Self.minimumRange else {
            rangeTooSmall = true
            // A narrow sweep is retried straight away; the countdown is not repeated.
            resetRange(keepReady: true)
            return
        }
        baselines[0] = low
        targets[0] = high
        best[0] = high
        initialized[0] = true
        rangeTooSmall = false
        progress = 0
        phase = .rangeResult
        narrationFinished = false
    }

    private func rangeGrew(from previousLow: Double?, and previousHigh: Double?) -> Bool {
        guard let previousLow, let previousHigh, let low = rangeLow, let high = rangeHigh else {
            return true
        }

        return low < previousLow - Self.rangeGrowthStep || high > previousHigh + Self.rangeGrowthStep
    }

    /// A wide enough range that has stopped growing needs no further sweeping.
    private var rangeHasSettled: Bool {
        guard let low = rangeLow, let high = rangeHigh, high - low >= Self.minimumRange else {
            return false
        }

        return rangeElapsed >= Self.rangeMinimumSweepSeconds
            && rangeElapsed - rangeGrowthElapsed >= Self.rangeSettleSeconds
    }

    /// Locks the direction of a forearm turn the first time the patient turns clearly away from
    /// the start pose. A turn that reads negative flips the sign, and the stored start pose with
    /// it, so the target is always "farther" in the direction the patient demonstrated.
    private mutating func adoptingForearmDirection(_ value: Double) -> Double {
        guard kind == .forearmRotation, phase == .target, !forearmDirectionLocked else {
            return value
        }

        let change = value - baselines[finger]

        guard abs(change) > Self.forearmTurnThreshold else {
            return value
        }

        forearmDirectionLocked = true

        guard change < 0 else {
            return value
        }

        forearmDirection = -forearmDirection
        baselines[finger] = -baselines[finger]
        resetHold()

        return -value
    }

    private mutating func resetRange(keepReady: Bool = false) {
        rangeReady = keepReady && rangeReady
        rangeElapsed = 0
        rangeLow = nil
        rangeHigh = nil
        rangeCandidate = nil
        rangeCandidateSum = 0
        rangeCandidateCount = 0
        rangeGrowthElapsed = 0
        progress = 0
    }

    private mutating func capture(_ value: Double, time: Double) {
        // A stationary hand outside the requested target must never run its hold clock.
        if phase == .target, !reachesTarget(value) {
            leaveZone(at: time)
            return
        }
        guard stable(value, time: time, tolerance: 0.10, duration: holdDuration) else {
            return
        }
        markHoldComplete()
    }

    private func reachesTarget(_ value: Double) -> Bool {
        value - baselines[finger] > Self.minimumTargetChange
            && touchesFingertip(value, holding: hold.isHolding)
    }

    /// Opposition is only done when the thumb tip actually meets the fingertip; getting most of
    /// the way there must not run the timer. Other exercises have no contact requirement.
    /// The opposition metric is the negative thumb-to-fingertip distance over palm length.
    private func touchesFingertip(_ value: Double, holding: Bool) -> Bool {
        guard kind == .opposition else {
            return true
        }

        return -value <= (holding ? Self.contactExit : Self.contactEntry)
    }

    mutating func holdCompletionPresented(_ id: UUID) {
        guard id == holdCompletionID, holdElapsed >= holdDuration else {
            return
        }
        holdCompletionWasPresented = true
    }

    private mutating func markHoldComplete() {
        guard holdCompletionID == nil else {
            return
        }
        progress = 1
        holdCompletionID = UUID()
        holdCompletionWasPresented = false
    }

    private mutating func commitCompletedHold() {
        guard holdCompletionID != nil, holdCompletionWasPresented, holdCount > 0 else {
            return
        }
        let mean = holdSum / Double(holdCount)
        switch phase {
        case .baseline:
            baselines[finger] = mean
            phase = .target
        case .target:
            targets[finger] = mean
            best[finger] = mean
            initialized[finger] = true
            if finger + 1 < calibrationCount {
                finger += 1
                metricFilter.reset()
                phase = .baseline
            } else {
                finger = 0
                metricFilter.reset()
                phase = .demonstration
                narrationFinished = false
            }
        case .active:
            if awaitingStart {
                awaitingStart = false
            } else if !returning {
                best[finger] = max(best[finger], mean)
                returning = true
            } else {
                returning = false
                peakStart = nil
                if kind.isSequential && finger < 3 {
                    finger += 1
                    metricFilter.reset()
                } else {
                    finger = 0
                    metricFilter.reset()
                    repetitions += 1
                    totalRepetitions += 1
                    if repetitions >= routine.repetitions {
                        completedSets += 1
                        phase = .feedback
                        remaining = 3
                        narrationFinished = false
                    }
                }
            }
        default:
            break
        }
        resetHold()
    }

    /// Leaving the zone briefly (detector wobble at the edge) freezes the hold; staying out clears it.
    private mutating func leaveZone(at time: Double) {
        if hold.isHolding, hold.interrupt(at: time, grace: InterruptibleHold.zoneExitGrace) {
            return
        }

        resetHold()
    }

    private mutating func resetHold() {
        hold.reset()
        holdSum = 0
        holdCount = 0
        holdCompletionID = nil
        holdCompletionWasPresented = false
        progress = 0
    }

    private mutating func stable(_ value: Double, time: Double, tolerance: Double, duration: Double) -> Bool {
        // A brief drift beyond tolerance (detector noise) freezes the hold; sustained drift restarts it.
        // After a few samples the pose is compared with the hold's average, not its first frame,
        // so one noisy starting frame cannot make the rest of the hold look like drift.
        let anchor = holdCount >= 3 ? holdSum / Double(holdCount) : holdValue

        if hold.isHolding, abs(value - anchor) > tolerance {
            leaveZone(at: time)

            if hold.isHolding {
                return false
            }
        }

        if !hold.isHolding {
            resetHold()
            holdValue = value
        }

        // Accumulate only fresh observed intervals; interrupted time is never credited.
        hold.credit(at: time)
        holdSum += value
        holdCount += 1
        progress = min(1, hold.elapsed / duration)

        return hold.elapsed >= duration
    }
}
