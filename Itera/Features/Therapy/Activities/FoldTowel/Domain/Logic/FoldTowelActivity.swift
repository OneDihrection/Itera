//
//  FoldTowelActivity.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Foundation

/// Owns gesture acceptance, four-fold repetitions and suspension recovery.
struct FoldTowelActivity: TherapyActivity {
    private let configuration: SessionActivity
    private var snapshot = TowelSnapshot()
    private var sequence = TowelFoldSequence()
    private var suspended = false
    private var last: Double?
    private var generation: UUID?
    private var countdownDeadline: Double?
    private var grip = TowelFoldSequence.Grip.uncertain
    private var viewport: TherapyViewport?

    init(configuration: SessionActivity) { self.configuration = configuration }

    var presentation: ActivityPresentation { .towel(snapshot) }

    mutating func handle(_ event: ActivityEvent) -> ActivityTransition {
        switch event {
        case .observation(let frame):
            if !suspended {
                consume(frame)
            }
        case .tick(let time):
            if !suspended, last.map({ time - $0 > 0.15 }) == true {
                loseTracking(at: time)
            }
            if !suspended, let deadline = countdownDeadline {
                snapshot.seconds = max(0, Int(ceil(deadline - time)))
                if time >= deadline {
                    countdownDeadline = nil
                    setPhase(.practice)
                }
            }
        case .guidanceCompleted:
            break
        case .countdownReady(let time):
            if snapshot.phase == .countdown, countdownDeadline == nil {
                countdownDeadline = time + 3
            }
        case .suspend:
            suspended = true
            sequence.suspend()
            loseTracking()
            countdownDeadline = nil
        case .resume:
            suspended = false
            if snapshot.phase == .countdown {
                setPhase(.countdown)
            }
        case .recalibrate:
            restart()
        case .nextSet:
            sequence = TowelFoldSequence()
            snapshot.count = 0
            setPhase(.countdown)
        case .viewport(let value):
            if let viewport, viewport != value {
                sequence.suspend()
                loseTracking()
            }
            viewport = value
        case .command(let command, _):
            switch command {
            case .redo, .retryStep:
                sequence.suspend()
                loseTracking()
                setPhase(.countdown)
            case .adjustTarget:
                restart()
            case .skipStep:
                break
            }
        }
        syncSequence()
        return ActivityTransition(
            status: snapshot.count >= configuration.goal ? .finished : (suspended ? .suspended : .running),
            presentation: presentation
        )
    }

    private mutating func restart() {
        let count = sequence.repetitions
        generation = nil
        sequence.suspend()
        snapshot = TowelSnapshot()
        snapshot.count = count
        countdownDeadline = nil
        loseTracking()
    }

    private mutating func loseTracking(at time: Double? = nil) {
        grip = .uncertain
        snapshot.grip = .uncertain
        snapshot.handPosition = nil
        snapshot.trackingMessage = "towel.trackingLost"
        sequence.trackingLost(at: time ?? last)
    }

    private mutating func setPhase(_ phase: TowelPhase) {
        snapshot.phase = phase
        snapshot.seconds = phase == .countdown ? 3 : 0
        snapshot.instruction = phase == .countdown ? "session.countdown" : "towel.approach"
    }

    private mutating func consume(_ frame: TrackingObservation) {
        guard frame.timestamp.isFinite, last.map({ frame.timestamp > $0 }) ?? true else {
            return
        }
        if let generation, generation != frame.generation {
            restart()
        }
        generation = frame.generation
        if last.map({ frame.timestamp - $0 > 0.15 }) == true {
            loseTracking()
        }
        last = frame.timestamp
        snapshot.imageAspect = frame.aspect
        guard let hand = frame.hand,
              hand.generation == frame.generation,
              hand.timestamp == frame.timestamp,
              hand.side?.rawValue == configuration.side.rawValue,
              let measurement = TowelHandMeasurement(hand) else {
            loseTracking()
            return
        }
        snapshot.trackingMessage = nil
        snapshot.grip = measurement.curl.map { classify($0) } ?? .uncertain
        let position = TherapyPoint(
            x: frame.workspaceMirrored ? 1 - measurement.position.x : measurement.position.x,
            y: measurement.position.y
        )
        snapshot.handPosition = position
        if snapshot.phase == .practice {
            sequence.consume(position: position, grip: snapshot.grip, timestamp: frame.timestamp)
        }
    }

    private mutating func classify(_ curl: Double) -> TowelFoldSequence.Grip {
        if grip == .open, curl <= 0.25 { return .open }
        if grip == .closed, curl >= 0.30 { return .closed }
        if curl <= 0.20 { grip = .open }
        else if curl >= 0.35 { grip = .closed }
        else { grip = .transitioning }
        return grip
    }

    private mutating func syncSequence() {
        snapshot.interaction = sequence.phase
        snapshot.holdProgress = sequence.holdProgress
        snapshot.grabID = sequence.grabID
        if snapshot.phase == .practice {
            switch sequence.phase {
            case .approach: snapshot.instruction = "towel.approach"
            case .grabbing: snapshot.instruction = "towel.grab"
            case .folding: snapshot.instruction = "towel.fold"
            case .destinationHold: snapshot.instruction = "towel.destinationHold"
            case .readyToRelease: snapshot.instruction = "towel.release"
            case .recovering: snapshot.instruction = "towel.recover"
            }
        }
        snapshot.count = sequence.repetitions
        snapshot.foldIndex = sequence.foldIndex
        snapshot.foldProgress = sequence.progress
        snapshot.grabPoint = sequence.grabPoint
        snapshot.destination = sequence.destination
    }
}
