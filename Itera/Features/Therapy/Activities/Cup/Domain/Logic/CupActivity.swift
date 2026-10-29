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
    private var wristStart: TherapyPoint?
    private var cupStart: TherapyPoint?
    private var faceTarget: TherapyPoint?
    private var transferTarget: TherapyPoint?
    private var hold = StableHold()
    private var cupHold = StableHold()
    private var viewport: TherapyViewport?
    private var suspended = false
    private var deadline: Double?
    private var last: Double?
    private var cupTimestamp: Double?
    private var boundary = 0.0
    private var restarting = false

    private var requiresCupEvidence: Bool {
        snapshot.step == .start || snapshot.step == .transfer || snapshot.step == .cupReturn
    }

    init(configuration: SessionActivity) {
        self.configuration = configuration
    }

    var presentation: ActivityPresentation { .cup(snapshot) }

    mutating func handle(_ event: ActivityEvent) -> ActivityTransition {
        switch event {
        case .command(let command, let time):
            receive(command, at: time)
        case .guidanceCompleted:
            break
        case .viewport(let value): viewport = value
        case .suspend:
            suspended = true
            clearHolds()
            if snapshot.phase == .practice {
                snapshot.step = .handReturn
                restarting = true
                snapshot.outcomes.removeAll { $0.round > snapshot.count }
            }
        case .resume:
            suspended = false
            last = nil
            if snapshot.phase == .countdown { deadline = nil }
        case .recalibrate:
            let count = snapshot.count
            let outcomes = snapshot.outcomes.filter { $0.round <= count }
            self = CupActivity(configuration: configuration)
            snapshot.count = count
            snapshot.outcomes = outcomes
        case .tick(let time):
            if let last, time - last > 0.3 {
                clearHolds()
                snapshot.evidenceMessage = requiresCupEvidence
                    ? "cup.evidenceMissing" : "cup.bodyTrackingLost"
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
                    wristStart = nil
                    cupStart = nil
                case .nearFace:
                    faceTarget = nil
                case .handReturn:
                    wristStart = nil
                    cupStart = nil
                    snapshot.step = .start
                case .transfer:
                    transferTarget = nil
                case .cupReturn:
                    transferTarget = nil
                }
            }
            boundary = time
            last = nil
            clearHolds()
        case .skipStep:
            break
        }
    }

    private mutating func clearHolds() {
        hold.clear()
        cupHold.clear()
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

    private func trackedPoint(wrist: TherapyPoint, cup: TherapyPoint?) -> TherapyPoint {
        cup ?? wrist
    }

    private mutating func consume(_ frame: TrackingObservation) {
        var time = frame.timestamp
        guard last.map({ time > $0 }) ?? true else { return }
        if let last, time - last > 0.3 { clearHolds() }
        last = time
        if snapshot.phase == .countdown {
            if deadline == nil { deadline = time + 3 }
            snapshot.seconds = max(0, Int(ceil((deadline ?? time) - time)))
            guard snapshot.seconds == 0 else { return }
            snapshot.phase = .practice
            boundary = time
        }
        guard snapshot.phase != .finished else { return }
        let left = configuration.side == .left
        guard let shoulder = frame.point(left ? .leftShoulder : .rightShoulder),
            let elbow = frame.point(left ? .leftElbow : .rightElbow),
            let wrist = frame.point(left ? .leftWrist : .rightWrist),
            let nose = frame.point(.nose)
        else {
            snapshot.evidenceMessage = "cup.bodyTrackingLost"
            clearHolds()
            return
        }
        let forearm = (wrist - elbow).length
        guard forearm > 0.015 else {
            snapshot.evidenceMessage = "cup.bodyTrackingLost"
            clearHolds()
            return
        }
        let bodyRadius = forearm * 0.2
        let requiresCup = requiresCupEvidence
        var cup: TherapyPoint?
        if requiresCup {
            guard let evidence = frame.cup, evidence.generation == frame.generation,
                evidence.timestamp > boundary, time - evidence.timestamp <= 0.3,
                evidence.timestamp <= time, evidence.centers.count == 1,
                let center = evidence.centers.first,
                center.x.isFinite, center.y.isFinite,
                evidence.bounds.count == 1
            else {
                snapshot.evidenceMessage = "cup.evidenceMissing"
                clearHolds()
                return
            }
            guard evidence.bounds[0].contains(wrist, margin: bodyRadius) else {
                snapshot.evidenceMessage = "cup.holdCup"
                clearHolds()
                return
            }
            guard cupTimestamp.map({ evidence.timestamp > $0 }) ?? true else { return }
            if cupTimestamp.map({ evidence.timestamp - $0 > 0.3 }) == true { clearHolds() }
            cupTimestamp = evidence.timestamp
            time = evidence.timestamp
            cup = center
        }
        snapshot.evidenceMessage = nil
        let rehearsing = snapshot.phase == .rehearsal
        defer {
            if snapshot.guide?.capturing == true {
                snapshot.guide?.progress = snapshot.progress
            }
        }
        if rehearsing {
            snapshot.guide = TargetGuide(
                start: trackedPoint(wrist: wrist, cup: cup), target: trackedPoint(wrist: wrist, cup: cup),
                tracked: trackedPoint(wrist: wrist, cup: cup), radius: bodyRadius, targetActive: false,
                progress: snapshot.progress, aspect: frame.aspect, capturing: true
            )
        }
        var target: TherapyPoint?
        let tracked = requiresCup ? (cup ?? wrist) : wrist
        switch snapshot.step {
        case .start:
            if !rehearsing {
                guard let cupStart else { clearHolds(); return }
                let radius = bubbleRadius(body: bodyRadius, separation: nil, aspect: frame.aspect, viewport: viewport)
                if (tracked - cupStart).length <= radius {
                    hold.consume(tracked, time: time, duration: 0.25, tolerance: radius * 2, maximumGap: 0.3)
                } else {
                    hold.clear()
                }
                snapshot.progress = hold.progress
                snapshot.guide = TargetGuide(start: cupStart, target: cupStart, tracked: tracked, radius: radius, targetActive: false, progress: hold.progress, aspect: frame.aspect)
                if hold.progress >= 1 { advance(at: time) }
                return
            }
            hold.consume(wrist - shoulder, time: time, duration: 1, tolerance: bodyRadius / 2, maximumGap: 0.3)
            cupHold.consume(cup ?? wrist, time: time, duration: 1, tolerance: bodyRadius / 2, maximumGap: 0.3)
            snapshot.progress = min(hold.progress, cupHold.progress)
            if snapshot.progress >= 1 {
                wristStart = hold.mean
                cupStart = cupHold.mean
                advance(at: time)
            }
            return
        case .nearFace:
            if rehearsing {
                guard (wrist - nose).length <= forearm * 1.5,
                    let wristStart, (wrist - (shoulder + wristStart)).length > bodyRadius * 2
                else { clearHolds(); return }
                hold.consume(wrist - nose, time: time, duration: 1, tolerance: bodyRadius / 2, maximumGap: 0.3)
                snapshot.progress = hold.progress
                if hold.progress >= 1 { faceTarget = hold.mean; advance(at: time) }
                return
            }
            target = faceTarget.map { nose + $0 }
        case .handReturn: target = wristStart.map { shoulder + $0 }
        case .transfer:
            if rehearsing {
                guard let cup, let cupStart else { clearHolds(); return }
                let offset = cup - cupStart
                guard abs(offset.x) >= abs(offset.y), offset.length > bodyRadius * 2 else {
                    clearHolds()
                    return
                }
                hold.consume(cup, time: time, duration: 1, tolerance: bodyRadius / 2, maximumGap: 0.3)
                snapshot.progress = hold.progress
                if hold.progress >= 1 { transferTarget = hold.mean; advance(at: time) }
                return
            }
            target = transferTarget
        case .cupReturn: target = cupStart
        }
        guard let target else { clearHolds(); return }
        let origin = requiresCup ? (cupStart ?? target) : wristStart.map { shoulder + $0 } ?? target
        let radius = bubbleRadius(
            body: bodyRadius, separation: (target - origin).length > 0 ? (target - origin).length : nil,
            aspect: frame.aspect, viewport: viewport
        )
        if (tracked - target).length <= radius {
            hold.consume(tracked, time: time, duration: 0.25, tolerance: radius * 2, maximumGap: 0.3)
        } else { hold.clear() }
        snapshot.progress = hold.progress
        snapshot.guide = TargetGuide(
            start: origin, target: target, tracked: tracked, radius: radius,
            targetActive: true, progress: hold.progress, aspect: frame.aspect
        )
        if hold.progress >= 1 { advance(at: time) }
    }
}
