//
//  FingerActivity.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

enum FingerPhase: Equatable {
    case baseline, target, demonstration, countdown, active, feedback, rest, finished
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
    private(set) var demonstrationSeconds = 0.0
    private(set) var baselines = [Double](repeating: 0, count: 4)
    private(set) var targets = [Double](repeating: 0, count: 4)
    private(set) var best = [Double](repeating: 0, count: 4)
    private var holdStart: Double?
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

    init(kind: FingerExercise, routine: FingerRoutine, restAfterFinalSet: Bool = true) {
        self.kind = kind
        self.routine = routine
        self.restAfterFinalSet = restAfterFinalSet
    }





    var needsStart: Bool { awaitingStart }
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

    // Evidence loss resets holds/cycles, independently of the preview-driven stage clock.
    mutating func suspendEvidence() {
        // Retain the accepted outward leg briefly, but credit no missing time or pending dwell.
        holdStart = nil
        peakStart = nil
        lastTimestamp = nil
        progress = 0
    }

    mutating func breakEvidence() {
        holdStart = nil
        peakStart = nil
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
        phase = .baseline
        finger = 0
        initialized = [Bool](repeating: false, count: 4)
        demonstrationSeconds = 0
        breakEvidence()
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
        let delta = min(0.2, max(0, now - (lastTick ?? now)))
        switch phase {
        case .demonstration, .feedback:
            if phase == .demonstration {
                demonstrationSeconds += delta
            }
            guard narrationFinished else {
                return
            }
            remaining -= delta
            if remaining <= 0 {
                if phase == .demonstration {
                    phase = .countdown
                    remaining = 3
                } else {
                    if completedSets >= routine.sets && !restAfterFinalSet {
                        phase = .finished
                    } else {
                        phase = .rest
                        remaining = Double(routine.restSeconds)
                    }
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
                    phase = .countdown
                    remaining = 3
                }
            }
        default:
            break
        }
    }

    mutating func observe(_ evidence: HandEvidence, now: Double) {
        guard now - evidence.timestamp >= 0, now - evidence.timestamp <= 0.3,
              evidence.timestamp > (lastTimestamp ?? -.infinity),
              let value = evidence.metric(for: kind, finger: finger), value.isFinite else {
            breakEvidence()
            return
        }
        let delta = evidence.timestamp - (lastTimestamp ?? evidence.timestamp)
        if delta > 0.15 {
            holdStart = nil
            peakStart = nil
            if delta > 0.5 {
                returning = false
                awaitingStart = true
            }
        }
        lastTimestamp = evidence.timestamp
        switch phase {
        case .baseline, .target:
            capture(value, time: evidence.timestamp)
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
                guard normalized <= 0.25 else {
                    holdStart = nil
                    return
                }
                if stable(value, time: evidence.timestamp, tolerance: range * 0.20, duration: 0.25) {
                    awaitingStart = false
                    holdStart = nil
                }
                return
            }
            progress = min(1, max(0, returning ? 1 - normalized : normalized))
            let arrived = returning ? normalized <= 0.25 : normalized >= 0.80
            guard arrived else {
                holdStart = nil
                return
            }
            guard stable(value, time: evidence.timestamp, tolerance: range * 0.20, duration: 0.25) else {
                return
            }
            if !returning {
                best[finger] = max(best[finger], holdSum / Double(holdCount))
                returning = true
            } else {
                returning = false
                peakStart = nil
                if kind.isSequential && finger < 3 {
                    finger += 1
                } else {
                    finger = 0
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
            holdStart = nil
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

    private mutating func capture(_ value: Double, time: Double) {
        guard stable(value, time: time, tolerance: 0.10, duration: 2) else {
            return
        }
        let mean = holdSum / Double(holdCount)
        if phase == .baseline {
            baselines[finger] = mean
            phase = .target
        } else {
            guard mean - baselines[finger] > 0.08 else {
                holdStart = nil
                progress = 0
                return
            }
            targets[finger] = mean
            best[finger] = mean
            initialized[finger] = true
            if finger + 1 < calibrationCount {
                finger += 1
                phase = .baseline
            } else {
                finger = 0
                phase = .demonstration
                remaining = kind.isSequential ? 16 : 8
                narrationFinished = false
            }
        }
        holdStart = nil
        progress = 0
    }

    private mutating func stable(_ value: Double, time: Double, tolerance: Double, duration: Double) -> Bool {
        if holdStart == nil || abs(value - holdValue) > tolerance {
            holdStart = time
            holdValue = value
            holdSum = 0
            holdCount = 0
        }
        holdSum += value
        holdCount += 1
        progress = min(1, (time - (holdStart ?? time)) / duration)
        return progress >= 1
    }
}
