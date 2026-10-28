//
//  DirectionalReachActivity.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

/// Shoulder-relative assessment, uncounted rehearsal, then complete ordered practice rounds.
struct DirectionalReachActivity: TherapyActivity {
    private enum Phase { case start, assess, assessReturn, countdown, outward, returning, finished }
    private let configuration: SessionActivity
    private var snapshot = ReachSnapshot()
    private var phase: Phase = .start
    private var start: TherapyPoint?
    private var targets: [Int: TherapyPoint] = [:]
    private var direction = 0
    private var rightSign = 1.0
    private var radius = 0.0
    private var hold = StableHold()
    private var farthest: TherapyPoint?
    private var elapsed = 0.0
    private var dwell: Double?
    private var last: Double?
    private var deadline: Double?
    private var suspended = false
    private var viewport: TherapyViewport?
    private var restartingRound = false
    private var awaitingGuidance = true
    private var preparingUntil: Double?
    private var pendingOutcomes: [ReachOutcome] = []

    init(configuration: SessionActivity) { self.configuration = configuration }
    var presentation: ActivityPresentation {
        var value = snapshot
        value.direction = direction
        value.round = snapshot.count + 1
        value.step = phaseIndex
        switch phase {
        case .start: value.phase = .setup
        case .assess, .assessReturn: value.phase = .assessment
        case .countdown: value.phase = .countdown
        case .outward, .returning: value.phase = snapshot.rehearsal ? .rehearsal : .practice
        case .finished: value.phase = .finished
        }
        return .reach(value)
    }

    mutating func handle(_ event: ActivityEvent) -> ActivityTransition {
        switch event {
        case .command(let command, let time):
            receive(command, at: time)
        case .guidanceCompleted(let time):
            if awaitingGuidance {
                awaitingGuidance = false
                if phase == .start { preparingUntil = time + 5 }
            }
        case .viewport(let value):
            viewport = value
            clearEvidence()
        case .suspend:
            suspended = true
            clearEvidence()
            // Partial practice milestones cannot survive an interruption.
            if phase == .outward || phase == .returning {
                direction = 0
                phase = .returning
                pendingOutcomes = []
                restartingRound = true
            }
        case .resume:
            suspended = false
            if phase == .start {
                awaitingGuidance = true
                preparingUntil = nil
            }
            if phase == .countdown { deadline = nil }
        case .recalibrate:
            phase = .start
            start = nil
            targets = [:]
            direction = 0
            elapsed = 0
            farthest = nil
            pendingOutcomes = []
            restartingRound = false
            snapshot.rehearsal = false
            snapshot.instruction = "session.reachStart"
            awaitingGuidance = true
            preparingUntil = nil
            clearEvidence()
        case .tick(let time):
            if last.map({ time - $0 > 0.3 }) == true { clearEvidence() }
        case .observation(let frame):
            if !suspended { consume(frame) }
        }
        return ActivityTransition(
            status: phase == .finished ? .finished : (suspended ? .suspended : .running),
            presentation: presentation)
    }

    private var phaseIndex: Int {
        switch phase {
        case .start: return 0
        case .assess, .assessReturn: return 1
        case .countdown: return 2
        case .outward, .returning: return snapshot.rehearsal ? 3 : 4
        case .finished: return 5
        }
    }

    private mutating func receive(_ command: ActivityCommand, at time: Double) {
        switch command {
        case .redo:
            let currentViewport = viewport
            self = DirectionalReachActivity(configuration: configuration)
            if let currentViewport {
                _ = handle(.viewport(currentViewport))
            }
        case .adjustTarget:
            guard phase == .assess || phase == .outward || phase == .returning else {
                return
            }
            targets.removeValue(forKey: direction)
            phase = .assess
            snapshot.rehearsal = false
            awaitingGuidance = false
            snapshot.instruction = directionKey
            resetAttempt()
        case .retryStep:
            switch phase {
            case .assess, .assessReturn:
                phase = .assess
                awaitingGuidance = false
                snapshot.instruction = directionKey
                resetAttempt()
            case .outward, .returning:
                phase = .returning
                direction = 0
                pendingOutcomes.removeAll()
                restartingRound = true
                resetAttempt()
            case .start, .countdown, .finished:
                break
            }
        case .skipStep:
            skipCurrentStep(at: time)
        }
    }

    private mutating func skipCurrentStep(at time: Double) {
        let skippedPhase: ReachSkippedStep.Phase
        if snapshot.rehearsal {
            skippedPhase = .rehearsal
        } else if phase == .assess || phase == .assessReturn {
            skippedPhase = .assessment
        } else {
            skippedPhase = .practice
        }

        switch phase {
        case .assess, .assessReturn:
            snapshot.caregiverSkippedSteps.append(
                ReachSkippedStep(round: 0, direction: direction, phase: .assessment))
            advanceAssessment(at: time)
        case .outward:
            snapshot.caregiverSkippedSteps.append(
                ReachSkippedStep(
                    round: snapshot.rehearsal ? 0 : snapshot.count + 1,
                    direction: direction,
                    phase: skippedPhase))
            phase = .returning
            resetAttempt()
        case .returning:
            snapshot.caregiverSkippedSteps.append(
                ReachSkippedStep(
                    round: snapshot.rehearsal ? 0 : snapshot.count + 1,
                    direction: direction,
                    phase: skippedPhase))
            advanceSkippedDirection(at: time)
        case .start, .countdown, .finished:
            break
        }
    }

    private mutating func advanceAssessment(at time: Double) {
        if direction < 2 {
            direction += 1
            phase = .assess
            awaitingGuidance = true
            snapshot.instruction = directionKey
            resetAttempt()
            return
        }

        phase = .countdown
        direction = 0
        snapshot.rehearsal = true
        snapshot.seconds = 3
        deadline = time + 3
        resetAttempt()
    }

    private mutating func advanceSkippedDirection(at time: Double) {
        if direction < 2 {
            direction += 1
            phase = .outward
        } else {
            direction = 0
            if snapshot.rehearsal {
                snapshot.rehearsal = false
                phase = .countdown
                snapshot.seconds = 3
                deadline = time + 3
            } else {
                pendingOutcomes.removeAll()
                phase = .outward
            }
        }
        resetAttempt()
    }

    private mutating func clearEvidence() {
        hold.clear()
        dwell = nil
        last = nil
        snapshot.guide = nil
        snapshot.progress = 0
    }

    private var directionKey: String {
        ["session.reachRight", "session.reachLeft", "session.reachUp"][direction]
    }
    private var vector: TherapyPoint {
        switch direction {
        case 0: return TherapyPoint(x: rightSign, y: 0)
        case 1: return TherapyPoint(x: -rightSign, y: 0)
        default: return TherapyPoint(x: 0, y: 1)
        }
    }

    private mutating func consume(_ frame: TrackingObservation) {
        let time = frame.timestamp
        guard time.isFinite, last.map({ time > $0 }) ?? true else {
            clearEvidence()
            return
        }
        let left = configuration.side == .left
        guard let shoulder = frame.point(left ? .leftShoulder : .rightShoulder),
            let elbow = frame.point(left ? .leftElbow : .rightElbow),
            let wrist = frame.point(left ? .leftWrist : .rightWrist),
            frame.point(.nose) != nil,
            let leftShoulder = frame.point(.leftShoulder),
            let rightShoulder = frame.point(.rightShoulder),
            abs(rightShoulder.x - leftShoulder.x) > 0.015,
            (wrist - elbow).length > 0.015
        else {
            snapshot.trackingMessage = "session.reachTrackingLost"
            clearEvidence()
            return
        }
        snapshot.trackingMessage = nil
        let sign = rightShoulder.x > leftShoulder.x ? 1.0 : -1.0
        if start != nil, sign != rightSign {
            _ = handle(.recalibrate)
            return
        }
        rightSign = sign
        let gap = last.map { time - $0 } ?? 0
        let delta = gap > 0 && gap <= 0.3 ? min(0.2, gap) : 0
        if gap > 0.3 {
            hold.clear()
            dwell = nil
        }
        last = time
        if radius == 0 { radius = (wrist - elbow).length * 0.2 }
        let relative = wrist - shoulder
        switch phase {
        case .start:
            snapshot.instruction = "session.reachStart"
            guard !awaitingGuidance, let preparingUntil else { return }
            snapshot.seconds = max(0, Int(ceil(preparingUntil - time)))
            guard time >= preparingUntil else { return }
            hold.consume(relative, time: time, duration: 1, tolerance: radius * 0.5, maximumGap: 0.3)
            snapshot.progress = hold.progress
            snapshot.guide = TargetGuide(
                start: wrist, target: wrist, tracked: wrist, radius: radius,
                targetActive: false, progress: hold.progress, aspect: frame.aspect
            )
            if hold.progress >= 1, let mean = hold.mean {
                start = mean
                phase = .assess
                awaitingGuidance = true
                snapshot.instruction = directionKey
                resetAttempt()
            }
        case .assess:
            guard let start else {
                return
            }
            snapshot.instruction = directionKey
            snapshot.guide = TargetGuide(
                start: shoulder + start, target: shoulder + start + vector.scaled(max(radius * 4, 0.08)),
                tracked: wrist, radius: radius, targetActive: true,
                progress: hold.progress, aspect: frame.aspect, directionOnly: true,
                farthest: farthest.map { shoulder + $0 }
            )
            guard !awaitingGuidance else { return }
            elapsed += delta
            snapshot.seconds = max(0, Int(ceil(8 - elapsed)))
            hold.consume(relative, time: time, duration: 1, tolerance: radius * 0.5, maximumGap: 0.3)
            snapshot.progress = hold.progress
            if hold.progress >= 1, let mean = hold.mean {
                let displacement = mean - start
                let forward = displacement.x * vector.x + displacement.y * vector.y
                let orthogonal = abs(displacement.x * vector.y - displacement.y * vector.x)
                let previous = farthest.map { ($0.x - start.x) * vector.x + ($0.y - start.y) * vector.y } ?? 0
                if forward > 0, forward >= orthogonal, forward > previous {
                    farthest = mean
                }
            }
            if elapsed >= 8 {
                if let farthest, (farthest - start).length > radius * 2 {
                    targets[direction] = farthest
                }
                phase = .assessReturn
                resetAttempt()
            }
        case .assessReturn:
            snapshot.instruction = "session.returnStart"
            if arrive(
                relative, shoulder: shoulder, wrist: wrist, frame: frame, outward: false, time: time
            ) {
                if direction < 2 {
                    direction += 1
                    phase = .assess
                    awaitingGuidance = true
                    snapshot.instruction = directionKey
                } else {
                    phase = .countdown
                    direction = 0
                    snapshot.rehearsal = true
                    snapshot.seconds = 3
                    deadline = time + 3
                }
                resetAttempt()
            }
        case .countdown:
            if deadline == nil { deadline = time + 3 }
            snapshot.instruction = "session.countdown"
            snapshot.seconds = max(0, Int(ceil((deadline ?? time) - time)))
            if time >= (deadline ?? time) {
                phase = .returning
                restartingRound = true
                resetAttempt()
            }
        case .outward:
            snapshot.instruction = directionKey
            elapsed += delta
            if !snapshot.rehearsal { snapshot.practiceSeconds += delta }
            snapshot.seconds = max(0, Int(ceil(8 - elapsed)))
            let reached = arrive(
                relative, shoulder: shoulder, wrist: wrist, frame: frame, outward: true, time: time)
            if reached || elapsed >= 8 {
                if !snapshot.rehearsal {
                    let evidence: ReachOutcome.Evidence =
                        targets[direction] == nil ? .unscored : (reached ? .reached : .notReached)
                    pendingOutcomes.append(ReachOutcome(direction: direction, evidence: evidence))
                }
                phase = .returning
                resetAttempt()
            }
        case .returning:
            snapshot.instruction = "session.returnStart"
            if !snapshot.rehearsal { snapshot.practiceSeconds += delta }
            if arrive(
                relative, shoulder: shoulder, wrist: wrist, frame: frame, outward: false, time: time
            ) {
                if restartingRound {
                    restartingRound = false
                    phase = .outward
                    resetAttempt()
                    return
                }
                if direction < 2 {
                    direction += 1
                } else {
                    direction = 0
                    if snapshot.rehearsal {
                        snapshot.rehearsal = false
                        phase = .outward
                        resetAttempt()
                        return
                    }
                    // Only all three outward attempts and returns form a round.
                    if pendingOutcomes.count == 3 {
                        snapshot.count += 1
                        snapshot.outcomes += pendingOutcomes
                    }
                    pendingOutcomes = []
                    if snapshot.count >= configuration.goal {
                        phase = .finished
                        return
                    }
                }
                phase = .outward
                resetAttempt()
            }
        case .finished: break
        }
    }

    private mutating func resetAttempt() {
        elapsed = 0
        farthest = nil
        hold.clear()
        dwell = nil
        last = nil
        snapshot.progress = 0
        snapshot.guide = nil
    }

    private mutating func arrive(
        _ relative: TherapyPoint, shoulder: TherapyPoint, wrist: TherapyPoint,
        frame: TrackingObservation, outward: Bool, time: Double
    ) -> Bool {
        guard let start else {
            return false
        }
        guard !outward || targets[direction] != nil else {
            snapshot.guide = nil
            return false
        }
        let target = targets[direction] ?? start
        let effective = bubbleRadius(
            body: radius, separation: target == start ? nil : (target - start).length,
            aspect: frame.aspect, viewport: viewport)
        let inside = (relative - (outward ? target : start)).length <= effective
        if !inside { dwell = nil }
        if inside, dwell == nil { dwell = time }
        let progress = inside ? min(1, (time - (dwell ?? time)) / 0.25) : 0
        snapshot.progress = progress
        snapshot.guide = TargetGuide(
            start: shoulder + start, target: shoulder + target, tracked: wrist, radius: effective,
            targetActive: outward, progress: progress, aspect: frame.aspect)
        if !outward {
            let tip = shoulder + start + vector.scaled(max(radius * 4, 0.08))
            snapshot.guide?.directionTip = tip
            snapshot.guide?.showsDirectionArrow = false
            snapshot.guide?.farthest = farthest.map { shoulder + $0 }
        }
        return progress >= 1
    }
}
