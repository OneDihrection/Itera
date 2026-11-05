//
//  CupActivity.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum CupStep: Int { case start, nearFace, handReturn, transfer, cupReturn }
enum CupPhase { case rehearsal, countdown, practice, finished }

struct CupMilestone: Codable, Equatable {
    let round: Int
    let step: Int
}

struct CupSnapshot {
    var phase: CupPhase = .rehearsal
    var step: CupStep = .start
    var instruction = "cup.start"
    var count = 0
    var progress = 0.0
    var seconds = 3
    var guide: TargetGuide?
    var outcomes: [CupMilestone] = []
    var evidenceMessage: String?
}

/// Rehearsal captures each target; only a complete practice sequence credits a round.
struct CupActivity: TherapyActivity {
    private let configuration: SessionActivity
    private var snapshot = CupSnapshot()
    private var cupStart: TherapyPoint?
    private var raisedTarget: TherapyPoint?
    private var transferTarget: TherapyPoint?
    private var hold = StableHold()
    private var calibratedRadius: Double?
    private var displayedCenter: TherapyPoint?
    private var displayTime: Double?
    private var viewport: TherapyViewport?
    private var suspended = false
    private var deadline: Double?
    private var last: Double?
    private var cupTimestamp: Double?
    private var boundary = 0.0
    private var trackID: UUID?
    private var restarting = false

    init(configuration: SessionActivity) {
        self.configuration = configuration
    }

    var presentation: ActivityPresentation { .cup(snapshot) }

    mutating func handle(_ event: ActivityEvent) -> ActivityTransition {
        switch event {
        case .nextSet:
            snapshot = CupSnapshot()
            snapshot.phase = .countdown
            snapshot.instruction = "session.countdown"
            deadline = nil
            last = nil
            cupTimestamp = nil
            restarting = false
            clearHolds()
        case .countdownReady(let time):
            if snapshot.phase == .countdown {
                deadline = time + 3
                snapshot.seconds = 3
            }
        case .command(let command, let time):
            receive(command, at: time)
        case .guidanceCompleted:
            break
        case .viewport(let value):
            if viewport != value {
                viewport = value
                clearHolds()
            }
        case .suspend:
            suspended = true
            loseEvidence(message: "cup.trackingLost")
        case .resume:
            suspended = false
            last = nil
            if snapshot.phase == .countdown { deadline = nil }
        case .recalibrate:
            let count = snapshot.count
            let outcomes = snapshot.outcomes.filter { $0.round <= count }
            let currentViewport = viewport
            self = CupActivity(configuration: configuration)
            viewport = currentViewport
            snapshot.count = count
            snapshot.outcomes = outcomes
        case .tick(let time):
            if let last, time - last > 0.3 {
                loseEvidence(message: "cup.trackingLost")
            }
        case .observation(let frame):
            if !suspended { consume(frame) }
        }
        return ActivityTransition(
            status: snapshot.phase == .finished ? .finished : (suspended ? .suspended : .running),
            presentation: presentation
        )
    }

    private mutating func receive(_ command: ActivityCommand, at time: Double) {
        switch command {
        case .redo:
            let currentViewport = viewport
            self = CupActivity(configuration: configuration)
            viewport = currentViewport
        case .adjustTarget:
            guard snapshot.phase == .rehearsal else { return }
            let currentViewport = viewport
            let count = snapshot.count
            let outcomes = snapshot.outcomes.filter { $0.round <= count }
            self = CupActivity(configuration: configuration)
            viewport = currentViewport
            snapshot.count = count
            snapshot.outcomes = outcomes
            boundary = time
        case .retryStep:
            if snapshot.phase == .practice {
                snapshot.outcomes.removeAll { $0.round > snapshot.count }
                snapshot.step = .nearFace
                restarting = false
            } else {
                switch snapshot.step {
                case .start:
                    cupStart = nil
                    calibratedRadius = nil
                case .nearFace:
                    raisedTarget = nil
                case .handReturn:
                    cupStart = nil
                    calibratedRadius = nil
                    snapshot.step = .start
                case .transfer:
                    transferTarget = nil
                case .cupReturn:
                    transferTarget = nil
                    snapshot.step = .transfer
                }
            }
            boundary = time
            last = nil
            clearHolds()
        case .skipStep:
            break
        }
    }

    private mutating func loseEvidence(message: String) {
        clearHolds()
        snapshot.evidenceMessage = message
        if snapshot.phase == .practice {
            snapshot.outcomes.removeAll { $0.round > snapshot.count }
            snapshot.step = .handReturn
            snapshot.instruction = "cup.handReturn"
            restarting = true
        }
    }

    private mutating func clearHolds() {
        hold.clear()
        displayedCenter = nil
        displayTime = nil
        snapshot.progress = 0
        snapshot.guide = nil
    }

    private mutating func advance(at time: Double) {
        if snapshot.phase == .practice, !restarting {
            snapshot.outcomes.append(CupMilestone(round: snapshot.count + 1, step: snapshot.step.rawValue))
        }
        clearHolds()
        boundary = time
        switch snapshot.step {
        case .start: snapshot.step = .nearFace
        case .nearFace: snapshot.step = .handReturn
        case .handReturn:
            snapshot.step = restarting ? .nearFace : .transfer
            restarting = false
        case .transfer: snapshot.step = .cupReturn
        case .cupReturn:
            if snapshot.phase == .rehearsal {
                snapshot.phase = .countdown
                deadline = time + 3
            } else {
                snapshot.count += 1
                if snapshot.count >= configuration.goal { snapshot.phase = .finished }
            }
            snapshot.step = snapshot.phase == .countdown ? .start : .nearFace
        }
        switch snapshot.step {
        case .start: snapshot.instruction = "cup.start"
        case .nearFace: snapshot.instruction = "cup.nearFace"
        case .handReturn: snapshot.instruction = "cup.handReturn"
        case .transfer: snapshot.instruction = "cup.transfer"
        case .cupReturn: snapshot.instruction = "cup.cupReturn"
        }
    }

    private mutating func consume(_ frame: TrackingObservation) {
        let time = frame.timestamp
        guard last.map({ time > $0 }) ?? true else { return }
        last = time
        guard snapshot.phase != .finished else { return }
        guard let evidence = frame.cup,
            evidence.generation == frame.generation,
            evidence.timestamp > boundary,
            evidence.state == .tracking,
            let identity = evidence.trackID,
            evidence.confidence.isFinite,
            let confirmation = evidence.lastDetectionTimestamp,
            confirmation.isFinite, confirmation <= evidence.timestamp,
            evidence.timestamp - confirmation <= 0.3,
            evidence.confidence >= (confirmation == evidence.timestamp ? 0.45 : 0.5),
            evidence.timestamp <= time,
            time - evidence.timestamp <= 0.3,
            evidence.centers.count == 1, evidence.bounds.count == 1,
            let center = evidence.centers.first,
            center.x.isFinite, center.y.isFinite,
            (0...frame.aspect).contains(center.x), (0...1).contains(center.y),
            evidence.bounds[0].contains(center, margin: 0)
        else {
            let message: String
            switch frame.cup?.state {
            case .ambiguous: message = "cup.ambiguous"
            case .lost: message = "cup.trackingLost"
            default: message = "cup.evidenceMissing"
            }
            loseEvidence(message: message)
            return
        }
        guard cupTimestamp.map({ evidence.timestamp > $0 }) ?? true else { return }
        if trackID != identity || cupTimestamp.map({ evidence.timestamp - $0 > 0.3 }) == true {
            loseEvidence(message: "cup.trackingLost")
        }
        trackID = identity
        cupTimestamp = evidence.timestamp
        snapshot.evidenceMessage = nil
        if let previous = displayedCenter, let displayTime {
            let alpha = 1 - exp(-(time - displayTime) / 0.06)
            displayedCenter = previous + (center - previous).scaled(alpha)
        } else {
            displayedCenter = center
        }
        displayTime = time
        if snapshot.phase == .countdown {
            guard let deadline else { return }
            snapshot.seconds = max(0, Int(ceil(deadline - time)))
            guard snapshot.seconds == 0 else { return }
            snapshot.phase = .practice
            boundary = time
            return
        }
        let box = evidence.bounds[0]
        let cupRadius = calibratedRadius ?? max(0.015, min(box.width, box.height) * 0.5)
        let capturing = snapshot.phase == .rehearsal
            && (snapshot.step == .start || snapshot.step == .nearFace || snapshot.step == .transfer)
        var guideRadius = bubbleRadius(body: cupRadius, separation: nil, aspect: frame.aspect, viewport: viewport)
        var target: TherapyPoint?
        var destination: TherapyPoint?
        var inside = false
        if capturing {
            if snapshot.step != .start {
                guard let cupStart else { return }
                let offset = center - cupStart
                let validDirection = snapshot.step == .transfer
                    ? abs(offset.x) >= abs(offset.y) : offset.y > 0
                guard validDirection, offset.length > cupRadius * 2 else {
                    hold.clear()
                    snapshot.progress = 0
                    snapshot.guide = TargetGuide(
                        start: cupStart, target: center, tracked: displayedCenter ?? center,
                        radius: guideRadius, targetActive: false, progress: 0,
                        aspect: frame.aspect, capturing: true, savedStart: true)
                    return
                }
            }
            hold.consume(center, time: evidence.timestamp, duration: 1,
                         tolerance: cupRadius / 2, maximumGap: 0.3)
            target = center
            destination = center
            inside = true
        } else {
            switch snapshot.step {
            case .nearFace: target = raisedTarget
            case .transfer: target = transferTarget
            case .start, .handReturn, .cupReturn: target = cupStart
            }
            guard let target else { clearHolds(); return }
            destination = snapshot.step == .transfer || snapshot.step == .cupReturn
                ? transferTarget : raisedTarget
            let separation = destination.flatMap { endpoint in
                cupStart.map { (endpoint - $0).length }
            }
            let radius = bubbleRadius(body: cupRadius,
                separation: separation,
                aspect: frame.aspect, viewport: viewport)
            guideRadius = radius
            inside = (center - target).length <= radius
            if inside {
                hold.consume(center, time: evidence.timestamp, duration: 1,
                             tolerance: radius * 2, maximumGap: 0.3)
            } else {
                hold.clear()
            }
        }
        guard let target else { return }
        snapshot.progress = hold.progress
        snapshot.guide = TargetGuide(
            start: cupStart ?? center, target: destination ?? target, tracked: displayedCenter ?? center,
            radius: guideRadius,
            targetActive: snapshot.step == .nearFace || snapshot.step == .transfer,
            progress: hold.progress, aspect: frame.aspect, capturing: capturing, savedStart: cupStart != nil,
            acceptedInside: inside)
        guard hold.progress >= 1 else { return }
        if capturing {
            switch snapshot.step {
            case .start:
                cupStart = hold.mean
                calibratedRadius = cupRadius
            case .nearFace: raisedTarget = hold.mean
            case .transfer: transferTarget = hold.mean
            case .handReturn, .cupReturn: break
            }
        }
        advance(at: time)
    }
}
