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
    private var dwell: Double?
    private var last: Double?
    private var lastValid: Double?
    private var viewport: TherapyViewport?
    private var suspended = false
    private var countdown: Double?
    private var returningBeforePractice = false
    private var cueHolding = false
    private var cueCandidate = false
    private var cueSince: Double?

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
            if snapshot.countingDown {
                snapshot.countingDown = false
                returningBeforePractice = true
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
            if let last, time - last > 0.15 {
                hold.clear()
                dwell = nil
                snapshot.progress = 0
            }
            if let lastValid, time - lastValid > 0.5 {
                phase = 0
                snapshot.guide = nil
                snapshot.trackingMessage = "session.movementTrackingLost"
            }
        case .observation(let frame):
            if !suspended {
                let filtered = landmarkSmoother.consume(frame)
                let left = configuration.side == .left
                let reference: BodyJoint = configuration.kind == .armRaise
                    ? (left ? .leftHip : .rightHip)
                    : (left ? .leftShoulder : .rightShoulder)
                let anchor: BodyJoint = configuration.kind == .armRaise
                    ? (left ? .leftShoulder : .rightShoulder)
                    : (left ? .leftElbow : .rightElbow)
                let tracked: BodyJoint = configuration.kind == .armRaise
                    ? (left ? .leftElbow : .rightElbow)
                    : (left ? .leftWrist : .rightWrist)
                if let a = frame.point(reference), let b = frame.point(anchor),
                   let c = frame.point(tracked),
                   (a - b).length > 0.03, (c - b).length > 0.03 {
                    consume(filtered)
                } else {
                    consume(frame)
                }
            }
        }
        let finished = snapshot.count >= configuration.goal
        return ActivityTransition(
            status: finished ? .finished : (suspended ? .suspended : .running),
            presentation: presentation
        )
    }

    private mutating func interrupt() {
        hold.clear()
        dwell = nil
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

    private mutating func consume(_ frame: TrackingObservation) {
        let time = frame.timestamp
        guard time.isFinite, last.map({ time > $0 }) ?? true else {
            interrupt()
            return
        }
        let gap = last.map { time - $0 } ?? 0
        if gap > 0.15 {
            hold.clear()
            dwell = nil
        }
        if gap > 0.5 { phase = 0 }
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
            hold.clear()
            dwell = nil
            snapshot.progress = 0
            snapshot.guide = nil
            snapshot.trackingMessage = "session.movementTrackingLost"
            if lastValid.map({ time - $0 > 0.5 }) == true { phase = 0 }
            return
        }
        let scale = (reference - anchor).length
        guard scale > 0.03, (tracked - anchor).length > 0.03 else {
            hold.clear()
            dwell = nil
            snapshot.guide = nil
            snapshot.progress = 0
            snapshot.trackingMessage = "session.movementTrackingLost"
            return
        }
        snapshot.trackingMessage = nil
        if lastValid.map({ time - $0 > 0.5 }) == true { phase = 0 }
        lastValid = time
        let offset = (tracked - anchor).scaled(1 / scale)
        if target == nil {
            if let start, (offset - start).length <= limb * 0.4 {
                hold.clear()
                snapshot.progress = 0
                snapshot.instruction = "session.farther"
                return
            }
            hold.consume(
                offset, time: time, duration: start == nil ? 5 : 3, tolerance: offset.length * 0.1)
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
            snapshot.guide = TargetGuide(
                start: start.map { anchor + $0.scaled(scale) } ?? tracked, target: tracked, tracked: tracked,
                radius: bubbleRadius(body: scale * offset.length * 0.2, separation: nil, aspect: frame.aspect, viewport: viewport),
                targetActive: false, progress: hold.progress, aspect: frame.aspect,
                capturing: true, savedStart: start != nil
            )
            snapshot.seconds = Int(ceil((start == nil ? 5 : 3) * (1 - hold.progress)))
            guard hold.progress >= 1, let mean = hold.mean else {
                return
            }
            if start == nil {
                start = mean
                limb = mean.length
                snapshot.pose = .peak
                snapshot.instruction = "parity.moveComfortably"
            } else if let start, (mean - start).length > limb * 0.4 {
                target = mean
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
        if let deadline = countdown {
            snapshot.instruction = "session.countdown"
            snapshot.seconds = max(0, Int(ceil(deadline - time)))
            snapshot.progress = max(0, min(1, (deadline - time) / 3))
            if time < deadline {
                return
            }
            countdown = nil
            snapshot.countingDown = false
            phase = 1
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
        if !inside { dwell = nil }
        if inside, dwell == nil { dwell = time }
        let progress = inside ? min(1, (time - (dwell ?? time)) / 0.25) : 0
        snapshot.instruction = phase == 1 ? "session.moveTarget" : "session.returnStart"
        snapshot.progress = progress
        snapshot.guide = TargetGuide(
            start: startCenter, target: targetCenter, tracked: tracked, radius: radius,
            targetActive: phase == 1, progress: progress, aspect: frame.aspect)
        guard progress >= 1 else {
            return
        }
        dwell = nil
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
