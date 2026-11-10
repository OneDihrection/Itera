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
    /// Last confirmed open or closed state, held through brief mid-curl frames.
    private var stableGrip: TowelFoldSequence.Grip?
    private var stableGripTime = 0.0
    private var cursorFilter = HandCursorFilter()
    private var pinchFilter = ScalarCursorFilter()
    /// Joints used last frame, so a joint hovering at the confidence cutoff does not flicker.
    private var measuredJoints: Set<Int> = []
    private var lastMeasured = 0.0
    private var viewport: TherapyViewport?

    /// Longest stretch of missing or weak evidence bridged by holding the last state.
    private static let dropoutBridge = 0.1

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
            cursorFilter.reset()
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
                cursorFilter.reset()
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
        cursorFilter.reset()
        sequence.suspend()
        snapshot = TowelSnapshot()
        snapshot.count = count
        countdownDeadline = nil
        loseTracking()
    }

    private mutating func loseTracking(at time: Double? = nil) {
        stableGrip = nil
        pinchFilter.reset()
        measuredJoints = []
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
              let measurement = TowelHandMeasurement(hand, retained: measuredJoints) else {
            // One missed or low-confidence frame keeps the last cursor and state instead of
            // flashing the hand away; the tick timeout still ends a real loss.
            if snapshot.handPosition != nil, frame.timestamp - lastMeasured <= Self.dropoutBridge {
                return
            }
            loseTracking()
            return
        }
        measuredJoints = measurement.joints
        lastMeasured = frame.timestamp
        snapshot.trackingMessage = nil
        if let pinch = measurement.pinch {
            let smoothed = pinchFilter.consume(pinch, at: frame.timestamp)
            snapshot.grip = classify(smoothed, at: frame.timestamp)
        } else {
            pinchFilter.reset()
            snapshot.grip = .uncertain
        }

        // Cursor and acceptance share one filtered point, so what is drawn is what is scored.
        let position = cursorFilter.consume(
            TherapyPoint(
                x: frame.workspaceMirrored ? 1 - measurement.position.x : measurement.position.x,
                y: measurement.position.y
            ),
            at: frame.timestamp
        )
        snapshot.handPosition = position
        if snapshot.phase == .practice {
            sequence.consume(position: position, grip: snapshot.grip, timestamp: frame.timestamp)
        }
    }

    // MARK: - Pinch thresholds

    // Ratios of thumb-to-index tip distance over palm length. Starting values pending device tuning.
    private static let pinchEnter = 0.25
    private static let pinchHold = 0.40
    private static let openEnter = 0.55
    private static let openHold = 0.45

    /// `.closed` means pinched. A pinch starts at a ratio of 0.25 and an open hand at 0.55, then each is
    /// held to 0.40 / 0.45 once confirmed. Mid-range frames keep the confirmed state for 0.15 s, so a
    /// half-formed detector sample does not read as a lost hand.
    private mutating func classify(_ pinch: Double, at time: Double) -> TowelFoldSequence.Grip {
        if stableGrip == .closed, pinch <= Self.pinchHold {
            stableGripTime = time
            return .closed
        }

        if stableGrip == .open, pinch >= Self.openHold {
            stableGripTime = time
            return .open
        }

        if pinch <= Self.pinchEnter {
            stableGrip = .closed
            stableGripTime = time
            return .closed
        }

        if pinch >= Self.openEnter {
            stableGrip = .open
            stableGripTime = time
            return .open
        }

        if let stableGrip, time - stableGripTime <= 0.15 {
            return stableGrip
        }

        return .transitioning
    }

    private mutating func syncSequence() {
        snapshot.interaction = sequence.phase
        snapshot.holdProgress = sequence.holdProgress
        snapshot.grabID = sequence.grabID
        if snapshot.phase == .practice {
            switch sequence.phase {
            case .approach: snapshot.instruction = "towel.approach"
            case .folding: snapshot.instruction = "towel.fold"
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
