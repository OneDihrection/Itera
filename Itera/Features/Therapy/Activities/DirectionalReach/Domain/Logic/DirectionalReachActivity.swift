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
    /// Upper arm plus forearm, frozen with `radius`; the farthest the wrist can sit from the shoulder.
    private var armLength = 0.0
    private var shoulderWidth = 0.0
    private var hold = StableHold()
    private var elapsed = 0.0
    private var dwell = InterruptibleHold()

    /// Seconds the wrist holds inside the target or start bubble before it is accepted.
    private static let dwellDuration = 2.0
    /// Seconds the wrist holds still to capture the start position and each candidate endpoint.
    private static let holdDuration = 2.0
    private var landmarkSmoother = MovementLandmarkSmoother()
    /// Longest tracking loss a dwell survives before it clears.
    private static let dwellTrackingGrace = 0.5
    private var last: Double?
    private var deadline: Double?
    private var suspended = false
    private var viewport: TherapyViewport?
    private var restartingRound = false
    private var awaitingGuidance = true
    private var pendingOutcomes: [ReachOutcome] = []
    private var missingSince: Double?
    private var recoveringSince: Double?

    /// Seconds evidence must be missing before the tracking message replaces the instruction.
    private static let trackingMessageDelay = 1.0
    /// Seconds evidence must stay good before the tracking message is hidden again.
    private static let trackingRecoveryDelay = 0.5
    /// Usable seconds without any accepted endpoint before a direction is left unscored.
    private static let assessmentIdleLimit = 30.0

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
        case .nextSet:
            snapshot = ReachSnapshot()
            snapshot.instruction = "session.countdown"
            snapshot.seconds = 3
            phase = .countdown
            direction = 0
            pendingOutcomes = []
            restartingRound = false
            awaitingGuidance = false
            deadline = nil
            resetAttempt()
        case .countdownReady(let time):
            if phase == .countdown {
                deadline = time + 3
                snapshot.seconds = 3
            }
        case .command(let command, let time):
            receive(command, at: time)
        case .guidanceCompleted:
            awaitingGuidance = false
        case .viewport(let value):
            viewport = value
            clearEvidence()
        case .suspend:
            suspended = true
            landmarkSmoother.reset()
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
            }
            if phase == .countdown { deadline = nil }
        case .recalibrate:
            landmarkSmoother.reset()
            phase = .start
            start = nil
            targets = [:]
            direction = 0
            elapsed = 0
            pendingOutcomes = []
            restartingRound = false
            snapshot.rehearsal = false
            snapshot.instruction = "session.reachStart"
            awaitingGuidance = true
            clearEvidence()
        case .tick(let time):
            if last.map({ time - $0 > 0.3 }) == true { clearEvidence() }
            if !suspended { advanceCountdown(at: time) }
        case .observation(let frame):
            if !suspended { consume(landmarkSmoother.consume(frame)) }
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
            snapshot.instruction = assessmentKey
            resetAttempt()
        case .retryStep:
            switch phase {
            case .assess, .assessReturn:
                phase = .assess
                awaitingGuidance = false
                snapshot.instruction = assessmentKey
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
            snapshot.instruction = assessmentKey
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
        dwell.reset()
        last = nil
        snapshot.guide = nil
        snapshot.progress = 0
    }

    /// Freezes a running dwell through brief tracking loss; clears everything once it lasts.
    ///
    /// The bubble stays at its last position with its ring paused, and no time is credited.
    private mutating func freezeEvidence(at time: Double) {
        hold.clear()

        guard dwell.isHolding,
              dwell.interrupt(at: time, grace: Self.dwellTrackingGrace) else {
            clearEvidence()
            return
        }
    }

    /// Shows the tracking message only after the evidence has been missing for a while, so a
    /// single dropped frame never swaps the cue text.
    private mutating func noteTrackingLoss(at time: Double) {
        recoveringSince = nil
        let since = missingSince ?? time
        missingSince = since

        if time - since >= Self.trackingMessageDelay {
            snapshot.trackingMessage = "session.reachTrackingLost"
        }
    }

    /// Hides the tracking message only after evidence has stayed good for a moment.
    private mutating func noteTrackingRecovery(at time: Double) {
        missingSince = nil

        guard snapshot.trackingMessage != nil else {
            recoveringSince = nil
            return
        }

        let since = recoveringSince ?? time
        recoveringSince = since

        if time - since >= Self.trackingRecoveryDelay {
            snapshot.trackingMessage = nil
            recoveringSince = nil
        }
    }

    /// Fraction of the ghost distance a held endpoint must cover to be accepted.
    private static let minimumReachFraction = 0.5
    /// Keeps the ghost this far inside the image edge, in image-height units.
    private static let ghostEdgeMargin = 0.06

    /// True when the arm reaches toward the opposite side of the body, which takes trunk rotation.
    private var isCrossDirection: Bool {
        let left = configuration.side == .left

        return (direction == 0 && left) || (direction == 1 && !left)
    }

    /// Cue for the assessment: reach as far as possible, and across the body for the cross side.
    private var assessmentKey: String {
        if isCrossDirection {
            return "session.reachAcross"
        }

        return ["session.reachRightFar", "session.reachLeftFar", "session.reachUpFar"][direction]
    }

    /// Distance from `origin` along the direction to the ghost, kept inside the image.
    ///
    /// The cross direction extends past the opposite shoulder, which an arm cannot reach
    /// without turning the trunk.
    private func ghostDistance(from origin: TherapyPoint, aspect: Double) -> Double {
        var distance = armLength * 0.95

        if isCrossDirection {
            distance = max(distance, shoulderWidth * 1.2)
        }

        let margin = Self.ghostEdgeMargin
        let xRoom = vector.x > 0 ? aspect - margin - origin.x : origin.x - margin
        let yRoom = vector.y > 0 ? 1 - margin - origin.y : origin.y - margin
        let room = min(
            vector.x == 0 ? .infinity : xRoom / abs(vector.x),
            vector.y == 0 ? .infinity : yRoom / abs(vector.y)
        )

        return max(radius * 4, min(distance, room))
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
            noteTrackingLoss(at: time)
            freezeEvidence(at: time)
            return
        }
        noteTrackingRecovery(at: time)
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
        }
        last = time
        if radius == 0 {
            radius = (wrist - elbow).length * 0.2
            armLength = (elbow - shoulder).length + (wrist - elbow).length
            shoulderWidth = abs(rightShoulder.x - leftShoulder.x)
        }
        let relative = wrist - shoulder
        switch phase {
        case .start:
            snapshot.instruction = "session.reachStart"
            guard !awaitingGuidance else { return }
            hold.consume(relative, time: time, duration: Self.holdDuration, tolerance: radius * 0.5, maximumGap: 0.3, wobbleGrace: 0.3)
            snapshot.progress = hold.progress
            snapshot.guide = TargetGuide(
                start: wrist, target: wrist, tracked: wrist, radius: radius,
                targetActive: false, progress: hold.progress, aspect: frame.aspect
            )
            if hold.progress >= 1, let mean = hold.mean {
                start = mean
                phase = .assess
                awaitingGuidance = true
                snapshot.instruction = assessmentKey
                resetAttempt()
            }
        case .assess:
            guard let start else {
                return
            }
            snapshot.instruction = assessmentKey
            // The ghost is anchored at the shoulder, not the resting wrist: left and right sit at
            // shoulder height and up sits above the shoulder, so the patient reaches out to the
            // sides and overhead as far as they can.
            let distance = ghostDistance(from: shoulder, aspect: frame.aspect)
            let ghost = vector.scaled(distance)
            snapshot.guide = TargetGuide(
                start: shoulder + start, target: shoulder + ghost,
                tracked: wrist, radius: radius, targetActive: true,
                progress: hold.progress, aspect: frame.aspect, jointHold: true
            )
            guard !awaitingGuidance else { return }
            elapsed += delta
            hold.consume(relative, time: time, duration: Self.holdDuration, tolerance: radius * 0.5, maximumGap: 0.3, wobbleGrace: 0.3)
            snapshot.progress = hold.progress
            snapshot.guide?.progress = hold.progress

            if hold.progress >= 1, let mean = hold.mean {
                // Measured along the line from the rest position to the ghost.
                let displacement = mean - start
                let toGhost = ghost - start
                let ghostLength = toGhost.length
                let axis = ghostLength > 0 ? toGhost.scaled(1 / ghostLength) : vector
                let forward = displacement.x * axis.x + displacement.y * axis.y
                let orthogonal = abs(displacement.x * axis.y - displacement.y * axis.x)

                // A token hop short of the ghost is not the farthest reach; the hold restarts.
                let reachedFar = forward >= ghostLength * Self.minimumReachFraction

                if forward > radius * 2, forward >= orthogonal, reachedFar {
                    targets[direction] = mean
                    phase = .assessReturn
                    resetAttempt()
                    return
                }

                // A steady hold in the wrong place starts over instead of being credited.
                hold.clear()
            }

            if elapsed >= Self.assessmentIdleLimit {
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
                    snapshot.instruction = assessmentKey
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
            advanceCountdown(at: time)
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

    /// Runs from the clock as well as from frames, so losing tracking never freezes the digit.
    private mutating func advanceCountdown(at time: Double) {
        guard phase == .countdown, let deadline else {
            return
        }

        snapshot.instruction = "session.countdown"
        snapshot.seconds = max(0, Int(ceil(deadline - time)))

        guard time >= deadline else {
            return
        }

        self.deadline = nil
        phase = .returning
        restartingRound = true
        resetAttempt()
    }

    private mutating func resetAttempt() {
        elapsed = 0
        hold.clear()
        dwell.reset()
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

        // Stepping out briefly or a jittery sample freezes the dwell; only a longer exit clears it.
        if inside {
            dwell.credit(at: time, maximumStep: 0.3)
        } else {
            dwell.interrupt(at: time, grace: InterruptibleHold.zoneExitGrace)
        }

        let progress = dwell.progress(duration: Self.dwellDuration)
        snapshot.progress = progress
        snapshot.guide = TargetGuide(
            start: shoulder + start, target: shoulder + target, tracked: wrist, radius: effective,
            targetActive: outward, progress: progress, aspect: frame.aspect)
        if !outward {
            let tip = shoulder + start + vector.scaled(max(radius * 4, 0.08))
            snapshot.guide?.directionTip = tip
            snapshot.guide?.showsDirectionArrow = false
        }
        guard progress >= 1 else {
            return false
        }

        // An accepted arrival must not carry its hold into the next zone.
        dwell.reset()

        return true
    }
}
