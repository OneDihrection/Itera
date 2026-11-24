//
//  FoldTowelActivity.swift
//  Tuntun
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
    /// Last confirmed open or closed state, held through brief mid-curl frames.
    private var stableGrip: TowelFoldSequence.Grip?
    private var stableGripTime = 0.0
    private var cursorFilter = HandCursorFilter()
    /// Fingertip jitter is far larger than the palm's, and the pinch offset changes slowly, so it
    /// is smoothed much harder than the palm. Starting values pending device tuning.
    private var offsetFilter = HandCursorFilter(minimumCutoff: 0.5, speedGain: 3)
    /// The last smoothed pinch offset, held while a fingertip is not measurable so the cursor
    /// does not jump back to the palm.
    private var heldOffset: TherapyPoint?
    private var pinchFilter = ScalarCursorFilter()
    /// Joints used last frame, so a joint hovering at the confidence cutoff does not flicker.
    private var measuredJoints: Set<Int> = []
    private var lastMeasured = 0.0
    /// The last preview frame that found the hand; kept apart from `lastMeasured` so previews
    /// never bridge a scored dropout.
    private var lastPreviewMeasured = 0.0
    private var viewport: TherapyViewport?

    /// Longest stretch of missing or weak evidence bridged by holding the last state.
    private static let dropoutBridge = 0.1

    init(configuration: SessionActivity) { self.configuration = configuration }

    var presentation: ActivityPresentation { .towel(snapshot) }

    mutating func handle(_ event: ActivityEvent) -> ActivityTransition {
        let before = presentation
        switch event {
        case .observation(let frame):
            if !suspended {
                consume(frame)
            }
        case .tick(let time):
            if !suspended, last.map({ time - $0 > 0.15 }) == true {
                loseTracking(at: time)
            }
        case .preview(let frame):
            if !suspended {
                previewTracking(frame)
            }
        case .guidanceCompleted:
            break
        case .countdownFinished:
            if snapshot.phase == .countdown {
                setPhase(.practice)
            }
        case .suspend:
            suspended = true
            resetCursor()
            sequence.suspend()
            loseTracking()
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
            snapshot.practiceSeconds = 0
            setPhase(.countdown)
        case .viewport(let value):
            if let viewport, viewport != value {
                resetCursor()
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
            presentation: presentation,
            facts: ActivityFact.changes(from: before, to: presentation)
        )
    }

    private mutating func restart() {
        let count = sequence.repetitions
        let practiceSeconds = snapshot.practiceSeconds
        generation = nil
        resetCursor()
        sequence.suspend()
        snapshot = TowelSnapshot()
        snapshot.count = count
        snapshot.practiceSeconds = practiceSeconds
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

    /// The frame's hand when it is the exercised one and belongs to this frame.
    private func exercisedHand(in frame: TrackingObservation) -> HandEvidence? {
        guard let hand = frame.hand,
              hand.generation == frame.generation,
              hand.timestamp == frame.timestamp,
              hand.side?.rawValue == configuration.side.rawValue else {
            return nil
        }

        return hand
    }

    /// While a cue holds scoring back, only the tracking message follows the hand, so the
    /// status chip stays live. Grip, cursor and fold sequence are left untouched.
    private mutating func previewTracking(_ frame: TrackingObservation) {
        guard frame.timestamp.isFinite else {
            return
        }

        guard let hand = exercisedHand(in: frame),
              TowelHandMeasurement(hand, retained: measuredJoints) != nil else {
            if frame.timestamp - lastPreviewMeasured > Self.dropoutBridge {
                snapshot.trackingMessage = "towel.trackingLost"
            }
            return
        }

        lastPreviewMeasured = frame.timestamp
        snapshot.trackingMessage = nil
    }

    private mutating func consume(_ frame: TrackingObservation) {
        guard frame.timestamp.isFinite, last.map({ frame.timestamp > $0 }) ?? true else {
            return
        }
        if let generation, generation != frame.generation {
            restart()
        }
        generation = frame.generation
        let gap = last.map { frame.timestamp - $0 } ?? 0
        if gap > 0.15 {
            loseTracking()
        }
        last = frame.timestamp
        snapshot.imageAspect = frame.aspect
        guard let hand = exercisedHand(in: frame),
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

        // Cursor and acceptance share one filtered point, so what is drawn is what is scored. The
        // palm carries the movement through the responsive filter; the pinch offset is smoothed
        // harder and held through fingertip dropouts. Both keep their image-coordinate tuning;
        // the workspace is mapped afterwards.
        let palm = cursorFilter.consume(
            TherapyPoint(
                x: frame.workspaceMirrored ? 1 - measurement.palm.x : measurement.palm.x,
                y: measurement.palm.y
            ),
            at: frame.timestamp
        )

        if let offset = measurement.pinchOffset {
            heldOffset = offsetFilter.consume(
                TherapyPoint(
                    x: frame.workspaceMirrored ? -offset.x : offset.x,
                    y: offset.y
                ),
                at: frame.timestamp
            )
        }

        let filtered = palm + (heldOffset ?? TherapyPoint(x: 0, y: 0))
        let position = workspacePoint(filtered, aspect: frame.aspect)
        snapshot.handPosition = position
        if snapshot.phase == .practice {
            // Practice time follows reach's rule: each measured frame credits at most 0.2 s, and
            // a gap over 0.3 s credits nothing.
            snapshot.practiceSeconds += gap > 0 && gap <= 0.3 ? min(0.2, gap) : 0
            sequence.consume(position: position, grip: snapshot.grip, timestamp: frame.timestamp)
        }
    }

    private mutating func resetCursor() {
        cursorFilter.reset()
        offsetFilter.reset()
        heldOffset = nil
    }

    // MARK: - Workspace

    /// Maps a normalized image point into the towel workspace, whose 0…1 spans only the part of
    /// the image the aspect-fill preview shows, so every zone and the towel stay on screen.
    /// Without a viewport yet the workspace is the whole image. A viewport change suspends the
    /// sequence, so one fold never mixes two mappings.
    private func workspacePoint(_ point: TherapyPoint, aspect: Double) -> TherapyPoint {
        guard let viewport else {
            return point
        }

        let visible = CameraDisplayGeometry(
            aspect: aspect,
            viewport: CGSize(width: viewport.width, height: viewport.height)
        ).visibleRect

        guard visible.width > 0, visible.height > 0 else {
            return point
        }

        return TherapyPoint(
            x: (point.x - visible.minX) / visible.width,
            y: (point.y - visible.minY) / visible.height
        )
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
