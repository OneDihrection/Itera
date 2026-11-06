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
    private var landmarkSmoother = MovementLandmarkSmoother()
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
                snapshot.trackingMessage = "session.movementTrackingLost"

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
        snapshot.trackingMessage = "session.movementTrackingLost"

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
        guard let reference = frame.point(referenceJoint),
            let anchor = frame.point(anchorJoint),
            let tracked = frame.point(trackedJoint)
        else {
            loseTracking(at: time)
            return
        }
        let scale = (reference - anchor).length
        guard scale > 0.03, (tracked - anchor).length > 0.03 else {
            loseTracking(at: time)
            return
        }
        snapshot.trackingMessage = nil
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
                radius: bubbleRadius(body: scale * offset.length * 0.2, separation: nil, aspect: frame.aspect, viewport: viewport),
                targetActive: false, progress: 0, aspect: frame.aspect,
                capturing: true, savedStart: start != nil
            )

            if let start, (offset - start).length <= limb * 0.4 {
                hold.clear()
                snapshot.progress = 0
                snapshot.seconds = Int(Self.captureDuration)
                cueHolding = false
                cueCandidate = false
                cueSince = nil
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
        let radius = bubbleRadius(
            body: limb * scale * 0.2, separation: (targetCenter - startCenter).length,
            aspect: frame.aspect, viewport: viewport)
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
            targetActive: phase == 1, progress: progress, aspect: frame.aspect)
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
}
