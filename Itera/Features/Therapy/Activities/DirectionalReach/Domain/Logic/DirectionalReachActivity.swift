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
    /// Farthest outward distance reached in the current assessment attempt, along the direction.
    private var peakForward = 0.0
    /// Shoulder-relative wrist position at `peakForward`.
    private var peakPoint: TherapyPoint?
    /// Recent valid outward samples, at most `peakWindow` old, so a single-frame extreme never
    /// becomes the peak.
    private var recentReach: [(point: TherapyPoint, time: Double)] = []

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
    /// Seconds without any frame before a tick clears holds and dwells. Frames arrive up to 0.3 s
    /// late, so a shorter limit would keep wiping holds that are still being fed.
    private static let trackingLossReset = 1.0
    /// Usable seconds each direction is assessed for; the farthest sustained reach becomes its target.
    private static let assessmentWindow = 8.0
    /// Seconds of trailing samples averaged into one reach candidate.
    private static let peakWindow = 0.4
    /// Seconds the trailing samples must span before their mean can become the peak.
    private static let peakMinimumSpan = 0.3

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
            if let last, time - last > Self.trackingLossReset {
                clearEvidence()
            }
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
        recentReach.removeAll(keepingCapacity: true)
        last = nil
        snapshot.guide = nil
        snapshot.progress = 0
    }

    /// Freezes a running dwell through brief tracking loss; clears everything once it lasts.
    ///
    /// The bubble stays at its last position with its ring paused, and no time is credited.
    private mutating func freezeEvidence(at time: Double) {
        hold.clear()
        recentReach.removeAll(keepingCapacity: true)

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

    /// Share of the measured maximum reach used as the practice target, so it can be hit repeatedly.
    private static let practiceTargetFraction = 0.85
    /// Seconds allowed to reach the practice target before the attempt counts as not reached.
    private static let outwardBudget = 12.0
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
            recentReach.removeAll(keepingCapacity: true)
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

            // The drawn bubble is the tolerance, so staying inside the ring the patient sees is
            // enough; a body-scaled tolerance was smaller than detector jitter.
            let tolerance = sharedBubbleRadius(aspect: frame.aspect, viewport: viewport)
            hold.consume(
                relative,
                time: time,
                duration: Self.holdDuration,
                tolerance: tolerance,
                maximumGap: 0.3,
                wobbleGrace: 0.3
            )
            snapshot.progress = hold.progress
            snapshot.guide = TargetGuide(
                start: wrist, target: wrist, tracked: wrist, radius: tolerance,
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
            // It is only a cue: it follows the farthest reach so it never acts as a ceiling.
            var distance = ghostDistance(from: shoulder, aspect: frame.aspect)
            if let peakPoint {
                distance = max(distance, peakPoint.x * vector.x + peakPoint.y * vector.y + radius * 2)
            }
            let ghost = vector.scaled(distance)
            snapshot.guide = TargetGuide(
                start: shoulder + start, target: shoulder + ghost,
                tracked: wrist, radius: radius, targetActive: true,
                progress: snapshot.progress, aspect: frame.aspect, jointHold: true
            )
            snapshot.guide?.farthest = peakPoint.map { shoulder + $0 }

            guard !awaitingGuidance else {
                return
            }

            // A fixed window of usable time: the patient reaches as far as they can, and the
            // farthest sustained point becomes the target once it ends.
            elapsed += delta
            snapshot.seconds = max(0, Int(ceil(Self.assessmentWindow - elapsed)))
            snapshot.progress = min(1, elapsed / Self.assessmentWindow)
            snapshot.guide?.progress = snapshot.progress
            snapshot.guide?.countdownSeconds = snapshot.seconds

            recordReach(relative, start: start, time: time)

            if elapsed >= Self.assessmentWindow {
                finishAssessmentWindow()
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
            snapshot.seconds = max(0, Int(ceil(Self.outwardBudget - elapsed)))
            let reached = arrive(
                relative, shoulder: shoulder, wrist: wrist, frame: frame, outward: true, time: time)
            if reached || elapsed >= Self.outwardBudget {
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

    /// Stores the practice target as a fraction of the measured reach and moves on to the return.
    private mutating func commitTarget(measured: TherapyPoint, start: TherapyPoint) {
        let offset = measured - start
        let length = offset.length
        let fraction = length > 0
            ? min(1, max(Self.practiceTargetFraction, radius * 2 / length))
            : 1.0

        targets[direction] = start + offset.scaled(fraction)
        phase = .assessReturn
        resetAttempt()
    }

    /// Feeds one shoulder-relative sample into the trailing window and raises the peak when the
    /// window's mean reaches farther.
    ///
    /// Reach is measured from the shoulder, like the ghost: a sample counts when the wrist lies
    /// within 45° of the direction seen from the shoulder and is out past the resting position by
    /// more than two body radii. Measuring from the hanging resting wrist instead put a reach at
    /// shoulder height exactly on the 45° edge, so reaching to or past the ghost was rejected.
    ///
    /// Any other sample empties the window, so the peak is always a reach sustained for
    /// `peakMinimumSpan`, never a single noisy frame.
    private mutating func recordReach(_ relative: TherapyPoint, start: TherapyPoint, time: Double) {
        let forward = shoulderForward(relative)
        let orthogonal = abs(relative.x * vector.y - relative.y * vector.x)

        guard forward > shoulderForward(start) + radius * 2,
              forward >= orthogonal
        else {
            recentReach.removeAll(keepingCapacity: true)
            return
        }

        recentReach.append((relative, time))
        recentReach.removeAll { time - $0.time > Self.peakWindow }

        guard let oldest = recentReach.first,
              time - oldest.time >= Self.peakMinimumSpan
        else {
            return
        }

        // The least extended sample is how far the wrist stayed out for the whole span, so a
        // spike inside the window cannot pull the candidate outward.
        var candidate = relative
        var candidateForward = forward

        for sample in recentReach {
            let sampleForward = shoulderForward(sample.point)

            if sampleForward < candidateForward {
                candidate = sample.point
                candidateForward = sampleForward
            }
        }

        guard candidateForward > peakForward else {
            return
        }

        peakForward = candidateForward
        peakPoint = candidate
    }

    /// Distance along the current direction of a shoulder-relative point.
    private func shoulderForward(_ point: TherapyPoint) -> Double {
        point.x * vector.x + point.y * vector.y
    }

    /// Ends the direction's window: the farthest sustained reach becomes its target; with no
    /// outward reach the direction stays unscored. Either way the patient returns to start.
    private mutating func finishAssessmentWindow() {
        if let start, let peakPoint {
            commitTarget(measured: peakPoint, start: start)
            return
        }

        phase = .assessReturn
        resetAttempt()
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
        peakForward = 0
        peakPoint = nil
        recentReach.removeAll(keepingCapacity: true)
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
        let effective = sharedBubbleRadius(aspect: frame.aspect, viewport: viewport)
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
