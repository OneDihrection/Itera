//
//  MovementActivity.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

struct MovementActivity: TherapyActivity {
    private let configuration: SessionActivity
    private var snapshot = MovementSnapshot()
    private var hold = StableHold()
    private var landmarkSmoother = MovementLandmarkSmoother(
        minimumConfidence: Self.jointConfidence,
        limbMinimumConfidence: Self.limbConfidence
    )
    private var start: TherapyPoint?
    private var target: TherapyPoint?
    private var limb = 0.0
    private var phase = 1
    private var dwell = InterruptibleHold()
    private var last: Double?
    private var lastValid: Double?
    private var viewport: TherapyViewport?
    private var suspended = false
    private var countdown: Double?
    private var returningBeforePractice = false
    private var cueHolding = false
    private var cueCandidate = false
    private var cueSince: Double?
    /// Turn direction of the calibration arrow, decided once per target capture.
    private var calibrationTurnSign: Double?
    private var calibrationCueVisible = true
    /// When usable evidence went missing, and when it came back while the message still shows.
    private var missingSince: Double?
    private var recoveringSince: Double?

    /// Confidence floor for the hip and shoulders.
    private static let jointConfidence: Float = 0.3
    /// Confidence floor for the elbow and wrist. It matches the live skeleton's floor, so an arm the
    /// patient sees drawn is never reported as missing; a wrist hanging beside the hip or folded in
    /// front of the body often scores below 0.5. The smoother's jump gate damps the extra noise.
    private static let limbConfidence: Float = 0.2
    /// Missing evidence shows the tracking message only after this long, so a dropped frame never
    /// swaps the cue text; good evidence clears it after `trackingRecoveryDelay`.
    private static let trackingMessageDelay = 1.0
    private static let trackingRecoveryDelay = 0.5

    /// The start bubble, target bubble and calibration ring all use the shared bubble size, so
    /// they match and stay clearly larger than the 28 pt joint marker.
    private func zoneRadius(aspect: Double) -> Double {
        sharedBubbleRadius(aspect: aspect, viewport: viewport)
    }

    /// Seconds the patient holds inside the start or target bubble before it is accepted.
    private static let dwellDuration = 2.0
    /// Seconds the patient holds still to capture the start and target positions.
    private static let captureDuration = 2.0
    /// Longest gap between fresh samples that still credits hold time. Slow frames with several
    /// people in view must not stop a hold from filling.
    private static let maximumCreditedStep = 0.3
    /// Fraction of the captured start-to-endpoint distance used as the practice target. 1.0 puts
    /// the target exactly on the held endpoint; the dwell and bubble radius absorb tremor and
    /// detector jitter. Lower it (0.9) to ask for less than the observed extreme.
    private static let targetFraction = 1.0
    /// Longest tracking loss a repetition dwell survives. Matches the phase reset below.
    private static let dwellTrackingGrace = 0.5

    init(configuration: SessionActivity) { self.configuration = configuration }
    var presentation: ActivityPresentation {
        var value = snapshot
        if snapshot.countingDown {
            value.phase = .countdown
        } else if target != nil {
            value.phase = returningBeforePractice ? .returnToStart : .practice
        } else {
            value.phase = start == nil ? .startCapture : .targetCapture
        }
        return .movement(value)
    }

    mutating func handle(_ event: ActivityEvent) -> ActivityTransition {
        switch event {
        case .countdownReady(let time):
            if snapshot.countingDown {
                countdown = time + 3
                snapshot.seconds = 3
            }
        case .nextSet:
            snapshot.count = 0
            interrupt()
            landmarkSmoother.reset()
            snapshot.countingDown = true
            snapshot.seconds = 3
            snapshot.instruction = "session.countdown"
            countdown = nil
            returningBeforePractice = false
        case .guidanceCompleted:
            break
        case .viewport(let value):
            if viewport != value {
                viewport = value
                interrupt()
            }
        case .suspend:
            suspended = true
            landmarkSmoother.reset()
            interrupt()
        case .resume:
            suspended = false

            // An interrupted countdown stays pending; the session re-announces it and sends
            // `countdownReady`, which starts a fresh three seconds.
            if snapshot.countingDown {
                countdown = nil
            }
        case .recalibrate:
            start = nil
            target = nil
            snapshot.countingDown = false
            snapshot.pose = .start
            snapshot.instruction = "session.holdStart"
            countdown = nil
            returningBeforePractice = false
            interrupt()
        case .command(let command, _):
            switch command {
            case .redo:
                let currentViewport = viewport
                self = MovementActivity(configuration: configuration)
                if let currentViewport {
                    _ = handle(.viewport(currentViewport))
                }
            case .adjustTarget:
                guard start != nil else { break }
                target = nil
                snapshot.countingDown = false
                returningBeforePractice = false
                countdown = nil
                snapshot.instruction = "session.holdTarget"
                interrupt()
            case .retryStep:
                guard target != nil else { break }
                phase = 0
                returningBeforePractice = false
                snapshot.instruction = "session.returnStart"
                interrupt()
            case .skipStep:
                break
            }
        case .tick(let time):
            advanceCountdown(at: time)

            if let last, time - last > 0.15 {
                dwell.interrupt(at: time, grace: Self.dwellTrackingGrace)

                if target == nil, !holdSurvivesLoss(at: time) {
                    hold.clear()
                    snapshot.progress = 0
                }
            }
            if let lastValid, time - lastValid > 0.5 {
                phase = 0
                // Without frames the loss began when evidence was last good.
                noteTrackingLoss(at: time, since: lastValid)

                if !holdSurvivesLoss(at: time) {
                    dwell.reset()
                    snapshot.guide = nil

                    if target != nil {
                        snapshot.progress = 0
                    }
                }
            }
        case .observation(let frame):
            if !suspended {
                let filtered = landmarkSmoother.consume(frame)
                consume(filtered)
            }
        }
        let finished = snapshot.count >= configuration.goal
        return ActivityTransition(
            status: finished ? .finished : (suspended ? .suspended : .running),
            presentation: presentation
        )
    }

    /// Runs the countdown from the clock as well as from frames, so a moment without a usable
    /// frame cannot freeze it. Finishing it starts practice at the target.
    private mutating func advanceCountdown(at time: Double) {
        guard snapshot.countingDown, let deadline = countdown, deadline > 0 else {
            return
        }

        snapshot.instruction = "session.countdown"
        snapshot.seconds = max(0, Int(ceil(deadline - time)))
        snapshot.progress = max(0, min(1, (deadline - time) / 3))

        guard time >= deadline else {
            return
        }

        countdown = nil
        snapshot.countingDown = false
        snapshot.progress = 0
        phase = 1
    }

    private mutating func interrupt() {
        hold.clear()
        dwell.reset()
        phase = 0
        last = nil
        lastValid = nil
        snapshot.guide = nil
        snapshot.progress = 0
        snapshot.trackingMessage = nil
        cueHolding = false
        cueCandidate = false
        cueSince = nil
        calibrationTurnSign = nil
        calibrationCueVisible = true
        missingSince = nil
        recoveringSince = nil
    }

    /// Shows the tracking message only after evidence has been missing for
    /// `trackingMessageDelay`, so a single weak frame never swaps the cue text.
    private mutating func noteTrackingLoss(at time: Double, since start: Double? = nil) {
        recoveringSince = nil
        let since = missingSince ?? start ?? time
        missingSince = since

        if time - since >= Self.trackingMessageDelay {
            snapshot.trackingMessage = "session.movementTrackingLost"
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

    /// Reads a joint at its own floor: the elbow and wrist at `limbConfidence`, others at
    /// `jointConfidence`, the same split the smoother uses.
    private func point(_ joint: BodyJoint, in frame: TrackingObservation) -> TherapyPoint? {
        switch joint {
        case .leftElbow, .rightElbow, .leftWrist, .rightWrist:
            return frame.point(joint, minimumConfidence: Self.limbConfidence)
        default:
            return frame.point(joint, minimumConfidence: Self.jointConfidence)
        }
    }

    /// A hold freezes, rather than clears, while tracking is briefly lost.
    ///
    /// Its bubble and progress stay on screen and no missing time is credited. A capture
    /// hold survives up to `InterruptibleHold.trackingGrace`; a repetition dwell survives
    /// only until the activity falls back to the start phase.
    private func holdSurvivesLoss(at time: Double) -> Bool {
        guard let lastValid else {
            return false
        }

        if target == nil {
            return hold.isActive && time - lastValid <= InterruptibleHold.trackingGrace
        }

        return dwell.isHolding && time - lastValid <= Self.dwellTrackingGrace
    }

    private mutating func loseTracking(at time: Double) {
        dwell.interrupt(at: time, grace: Self.dwellTrackingGrace)
        noteTrackingLoss(at: time)

        if lastValid.map({ time - $0 > 0.5 }) == true {
            phase = 0
        }

        guard !holdSurvivesLoss(at: time) else {
            return
        }

        hold.clear()
        dwell.reset()
        snapshot.progress = 0
        snapshot.guide = nil
    }

    /// The arm is in view but the tracked segment is too short to measure, such as a forearm
    /// pointing at the camera. Nothing is credited: the dwell freezes and a capture hold earns no
    /// time (it restarts by itself if the gap outlasts its grace). The arm is not reported
    /// missing, and the indicator stays on the joint.
    private mutating func freezeForShortSegment(at time: Double, tracked: TherapyPoint) {
        dwell.interrupt(at: time, grace: Self.dwellTrackingGrace)
        noteTrackingRecovery(at: time)
        lastValid = time
        snapshot.guide?.tracked = tracked
    }

    private mutating func consume(_ frame: TrackingObservation) {
        let time = frame.timestamp
        guard time.isFinite, last.map({ time > $0 }) ?? true else {
            interrupt()
            return
        }
        let gap = last.map { time - $0 } ?? 0
        if gap > 0.5 {
            phase = 0
            dwell.reset()
        }
        last = time
        let left = configuration.side == .left
        let referenceJoint: BodyJoint =
            configuration.kind == .armRaise
            ? (left ? .leftHip : .rightHip) : (left ? .leftShoulder : .rightShoulder)
        let anchorJoint: BodyJoint =
            configuration.kind == .armRaise
            ? (left ? .leftShoulder : .rightShoulder) : (left ? .leftElbow : .rightElbow)
        let trackedJoint: BodyJoint =
            configuration.kind == .armRaise
            ? (left ? .leftElbow : .rightElbow) : (left ? .leftWrist : .rightWrist)
        guard let reference = point(referenceJoint, in: frame),
            let anchor = point(anchorJoint, in: frame),
            let tracked = point(trackedJoint, in: frame)
        else {
            loseTracking(at: time)
            return
        }
        let scale = (reference - anchor).length
        guard scale > 0.03 else {
            loseTracking(at: time)
            return
        }
        guard (tracked - anchor).length > 0.03 else {
            freezeForShortSegment(at: time, tracked: tracked)
            return
        }
        noteTrackingRecovery(at: time)
        if lastValid.map({ time - $0 > 0.5 }) == true {
            phase = 0
            dwell.reset()
        }
        lastValid = time
        let offset = (tracked - anchor).scaled(1 / scale)
        if target == nil {
            // Keep live geometry visible even when this position cannot be captured.
            snapshot.guide = TargetGuide(
                start: start.map { anchor + $0.scaled(scale) } ?? tracked, target: tracked, tracked: tracked,
                radius: zoneRadius(aspect: frame.aspect),
                targetActive: false, progress: 0, aspect: frame.aspect,
                capturing: true, savedStart: start != nil,
                pivot: anchor
            )

            // Once the start is saved, the calibration cue shows which way to move. It is a fixed
            // path from the saved start around the pivot, so the limb moves through it instead of
            // the cue following the limb. Its turn direction is decided once per capture, so joint
            // jitter cannot swing it from side to side.
            var turnTip: TherapyPoint?

            if let start {
                let startPoint = anchor + start.scaled(scale)
                let sign = calibrationTurnSign ?? calibrationTurnSign(
                    anchor: anchor,
                    reference: reference,
                    tracked: startPoint,
                    otherShoulder: point(left ? .rightShoulder : .leftShoulder, in: frame)
                )
                calibrationTurnSign = sign
                turnTip = calibrationTip(anchor: anchor, reference: reference, from: startPoint, sign: sign)
            }

            if let start, (offset - start).length <= limb * 0.4 {
                hold.clear()
                snapshot.progress = 0
                snapshot.seconds = Int(Self.captureDuration)
                cueHolding = false
                cueCandidate = false
                cueSince = nil
                calibrationCueVisible = true
                snapshot.guide?.calibrationTip = turnTip
                snapshot.instruction = "session.farther"
                return
            }
            // Brief tracking loss or a stray sample freezes the hold; neither earns credit.
            hold.consume(
                offset,
                time: time,
                duration: Self.captureDuration,
                tolerance: offset.length * 0.1,
                maximumGap: InterruptibleHold.trackingGrace,
                creditedStep: 0.15,
                wobbleGrace: InterruptibleHold.zoneExitGrace
            )
            snapshot.progress = hold.progress

            // Hide the arrow only after half a second of real stillness, and bring it back only
            // when the hold restarts, so ordinary movement never makes it blink.
            if hold.progress >= Self.calibrationCueHideProgress {
                calibrationCueVisible = false
            } else if hold.progress == 0 {
                calibrationCueVisible = true
            }

            snapshot.guide?.calibrationTip = calibrationCueVisible ? turnTip : nil
            let candidate = hold.progress > 0
            if cueCandidate != candidate || cueSince == nil {
                cueCandidate = candidate
                cueSince = time
            }
            if let cueSince, time - cueSince >= (candidate ? 0.4 : 0.6) {
                cueHolding = candidate
            }
            snapshot.instruction = start == nil ? "session.holdStart" : (cueHolding ? "session.holdTarget" : "parity.moveComfortably")
            snapshot.guide?.progress = hold.progress
            snapshot.seconds = Int(ceil(Self.captureDuration * (1 - hold.progress)))
            guard hold.progress >= 1, let mean = hold.mean else {
                return
            }
            if start == nil {
                start = mean
                limb = mean.length
                snapshot.pose = .peak
                snapshot.instruction = "parity.moveComfortably"
            } else if let start, (mean - start).length > limb * 0.4 {
                target = start + (mean - start).scaled(Self.targetFraction)
                calibrationTurnSign = nil
                snapshot.instruction = "session.returnStart"
                returningBeforePractice = true
                snapshot.countingDown = false
                countdown = nil
                snapshot.pose = .looping
                phase = 0
            }
            hold.clear()
            snapshot.progress = 0
            snapshot.guide = nil
            return
        }
        if countdown == -1 { countdown = time + 3 }
        if countdown != nil {
            advanceCountdown(at: time)

            if snapshot.countingDown {
                return
            }
        } else if snapshot.countingDown {
            // Waiting for the session to start the countdown: nothing is scored yet.
            snapshot.guide = nil
            return
        }
        guard let start, let target else {
            return
        }
        let startCenter = anchor + start.scaled(scale)
        let targetCenter = anchor + target.scaled(scale)
        let radius = zoneRadius(aspect: frame.aspect)
        let active = phase == 1 ? targetCenter : startCenter
        let inside = (tracked - active).length <= radius

        // Stepping out briefly or a jittery sample freezes the dwell; only a longer exit clears it.
        if inside {
            dwell.credit(at: time, maximumStep: Self.maximumCreditedStep)
        } else {
            dwell.interrupt(at: time, grace: InterruptibleHold.zoneExitGrace)
        }

        let progress = dwell.progress(duration: Self.dwellDuration)
        snapshot.instruction = phase == 1 ? "session.moveTarget" : "session.returnStart"
        snapshot.progress = progress
        snapshot.guide = TargetGuide(
            start: startCenter, target: targetCenter, tracked: tracked, radius: radius,
            targetActive: phase == 1, progress: progress, aspect: frame.aspect,
            pivot: anchor)
        guard progress >= 1 else {
            return
        }
        dwell.reset()
        if returningBeforePractice {
            returningBeforePractice = false
            countdown = time + 3
            snapshot.countingDown = true
            snapshot.seconds = 3
            snapshot.guide = nil
        } else if phase == 2 {
            snapshot.count += 1
            phase = 1
        } else {
            phase = phase == 0 ? 1 : 2
        }
    }

    // MARK: - Calibration cue

    /// Turn, in radians, used to tell which way the limb bends when choosing the cue's direction.
    private static let calibrationTurn = Double.pi / 3
    /// How far the calibration cue's fixed path sweeps from the saved start, in radians: past
    /// where a comfortable end usually lies, so the limb stays inside it.
    private static let calibrationSweep = 2 * Double.pi / 3
    /// Within this angle of the reference line the turn's sign is unreliable, in radians.
    private static let ambiguousTurn = 15 * Double.pi / 180
    /// Gap kept from the reference line so an elbow-bend arrow never crosses the upper arm.
    private static let turnMargin = 10 * Double.pi / 180

    /// Calibration arrow hides once the hold reaches this progress: half a second of stillness.
    private static let calibrationCueHideProgress = 0.25

    /// Which way the calibration arrow turns the limb around the anchor (+1 counterclockwise):
    /// away from the hip for an arm raise, toward the shoulder for an elbow bend.
    ///
    /// When the limb lies almost along its reference line, which way it bends cannot be told from
    /// the image, so an arm raise turns outward (away from the other shoulder) and an elbow bend
    /// inward. The caller keeps the result for the whole capture.
    private func calibrationTurnSign(
        anchor: TherapyPoint,
        reference: TherapyPoint,
        tracked: TherapyPoint,
        otherShoulder: TherapyPoint?
    ) -> Double {
        let segment = tracked - anchor
        let toward = reference - anchor
        let cross = toward.x * segment.y - toward.y * segment.x
        let raising = configuration.kind == .armRaise
        let angle = Self.angleFromReference(segment, reference: toward)
        let ambiguous = raising
            ? angle < Self.ambiguousTurn
            : angle > .pi - Self.ambiguousTurn

        if ambiguous, let otherShoulder {
            let outward = anchor - otherShoulder
            let counterclockwise = Self.rotated(segment, by: Self.calibrationTurn)
            let clockwise = Self.rotated(segment, by: -Self.calibrationTurn)
            let counterclockwiseIsOutward =
                counterclockwise.x * outward.x + counterclockwise.y * outward.y
                >= clockwise.x * outward.x + clockwise.y * outward.y
            let outwardSign = counterclockwiseIsOutward ? 1.0 : -1.0

            return raising ? outwardSign : -outwardSign
        }

        // With a positive cross, a counterclockwise turn moves away from the reference.
        let awaySign = cross >= 0 ? 1.0 : -1.0

        return raising ? awaySign : -awaySign
    }

    /// Where the calibration cue ends: the saved start turned `sign`-wise around the anchor by up
    /// to `calibrationSweep`. An elbow-bend turn shrinks near the upper arm and stops before
    /// crossing it, so the cue never points through the shoulder.
    private func calibrationTip(
        anchor: TherapyPoint,
        reference: TherapyPoint,
        from startPoint: TherapyPoint,
        sign: Double
    ) -> TherapyPoint {
        let segment = startPoint - anchor
        let toward = reference - anchor
        var turn = Self.calibrationSweep

        if configuration.kind != .armRaise {
            let cross = toward.x * segment.y - toward.y * segment.x
            let angle = Self.angleFromReference(segment, reference: toward)
            let turnsTowardReference = (cross >= 0 ? -1.0 : 1.0) == sign
            // Turning "away" from a nearly straight arm still swings round toward the shoulder on
            // the other side; only a forearm already folded past the upper arm has no room.
            let room: Double

            if turnsTowardReference {
                room = angle - Self.turnMargin
            } else {
                room = angle >= .pi / 2 ? Self.calibrationSweep : 0
            }

            turn = max(0, min(turn, room))
        }

        return anchor + Self.rotated(segment, by: sign * turn)
    }

    /// 0 along the reference line, π pointing away from it.
    private static func angleFromReference(_ segment: TherapyPoint, reference: TherapyPoint) -> Double {
        let cross = reference.x * segment.y - reference.y * segment.x
        let dot = reference.x * segment.x + reference.y * segment.y

        return atan2(abs(cross), dot)
    }

    private static func rotated(_ vector: TherapyPoint, by angle: Double) -> TherapyPoint {
        TherapyPoint(
            x: vector.x * cos(angle) - vector.y * sin(angle),
            y: vector.x * sin(angle) + vector.y * cos(angle)
        )
    }
}
