//
//  TowelFoldSequence.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Foundation

/// Evidence-driven folding in normalized preview coordinates. Display interpolation never scores.
struct TowelFoldSequence {
    enum Grip { case open, closed, transitioning, uncertain }
    enum Phase { case approach, grabbing, folding, destinationHold, readyToRelease, recovering }

    private(set) var foldIndex = 0
    private(set) var repetitions = 0
    private(set) var progress = 0.0
    private(set) var holdProgress = 0.0
    private(set) var phase = Phase.approach
    private(set) var grabID = 0
    private var lastTimestamp: Double?
    private var pendingSince: Double?
    private var arrivalSince: Double?
    private var missingSince: Double?
    private var recoverySince: Double?
    private var lastPosition: TherapyPoint?
    private var travelOrigin: TherapyPoint?
    private var travelPath = TherapyPoint(x: 0, y: 0)
    private var baseProgress = 0.0

    var horizontal: Bool { foldIndex % 2 == 0 }
    var grabPoint: TherapyPoint {
        horizontal ? TherapyPoint(x: 0.8, y: 0.5) : TherapyPoint(x: 0.5, y: 0.2)
    }
    var destination: TherapyPoint {
        horizontal ? TherapyPoint(x: 0.2, y: 0.5) : TherapyPoint(x: 0.5, y: 0.8)
    }

    mutating func suspend() {
        foldIndex = 0
        cancelGrasp()
        lastTimestamp = nil
    }

    mutating func trackingLost(at time: Double? = nil) {
        pendingSince = nil
        arrivalSince = nil
        recoverySince = nil
        holdProgress = 0
        guard let time, time.isFinite,
              phase == .folding || phase == .destinationHold || phase == .readyToRelease || phase == .recovering else {
            cancelGrasp()
            return
        }
        if missingSince == nil { missingSince = time }
        phase = .recovering
        if time - (missingSince ?? time) > 0.3 { cancelGrasp() }
    }

    mutating func consume(position: TherapyPoint, grip: Grip, timestamp: Double) {
        guard timestamp.isFinite, position.x.isFinite, position.y.isFinite else {
            trackingLost()
            return
        }
        guard lastTimestamp.map({ timestamp > $0 }) ?? true else { return }
        if let lastTimestamp, timestamp - lastTimestamp > 0.15 {
            if phase == .recovering {
                cancelGrasp()
            } else {
                trackingLost(at: lastTimestamp)
            }
        }
        lastTimestamp = timestamp

        if phase == .recovering {
            recover(position: position, grip: grip, timestamp: timestamp)
            return
        }
        guard grip != .uncertain && grip != .transitioning else {
            trackingLost(at: timestamp)
            return
        }
        lastPosition = position
        let atGrab = (position - grabPoint).length <= 0.12
        let atDestination = (position - destination).length <= 0.12
        switch phase {
        case .approach, .grabbing:
            guard atGrab, grip == .closed else {
                cancelGrasp()
                return
            }
            phase = .grabbing
            if held(at: timestamp, duration: 0.2) {
                phase = .folding
                grabID += 1
                travelOrigin = position
                travelPath = destination - position
                baseProgress = 0
                clearHold()
            }
        case .folding, .destinationHold:
            guard grip == .closed, let origin = travelOrigin else {
                cancelGrasp()
                return
            }
            let path = travelPath
            let offset = position - origin
            if path.length > 0.001 {
                let projection = (offset.x * path.x + offset.y * path.y) / (path.length * path.length)
                let perpendicular = abs(offset.x * path.y - offset.y * path.x) / path.length
                guard perpendicular <= 0.15 else {
                    arrivalSince = nil
                    holdProgress = 0
                    phase = .folding
                    return
                }
                progress = min(1, max(0, baseProgress + projection))
            }
            guard atDestination else {
                arrivalSince = nil
                holdProgress = 0
                phase = .folding
                return
            }
            phase = .destinationHold
            if arrivalSince == nil { arrivalSince = timestamp }
            holdProgress = min(1, (timestamp - (arrivalSince ?? timestamp)) / 0.5)
            if holdProgress >= 1 {
                progress = 1
                phase = .readyToRelease
                clearHold()
            }
        case .readyToRelease:
            guard atDestination else {
                cancelGrasp()
                return
            }
            if grip == .open, held(at: timestamp, duration: 0.3) {
                foldIndex += 1
                if foldIndex == 4 {
                    repetitions += 1
                    foldIndex = 0
                }
                cancelGrasp()
            } else if grip == .closed {
                clearHold()
            }
        case .recovering:
            break
        }
    }

    private mutating func recover(position: TherapyPoint, grip: Grip, timestamp: Double) {
        guard let missingSince else {
            cancelGrasp()
            return
        }
        // The first usable sample must return within the grace period. Confirmation then
        // gets its own contiguous 200 ms window, rather than expiring during that hold.
        if recoverySince == nil {
            guard timestamp - missingSince <= 0.3, grip == .closed else {
                if timestamp - missingSince > 0.3 || grip == .open { cancelGrasp() }
                return
            }
            recoverySince = timestamp
            lastPosition = position
        }
        guard grip == .closed, let lastPosition, (position - lastPosition).length <= 0.12 else {
            cancelGrasp()
            return
        }
        holdProgress = min(1, (timestamp - (recoverySince ?? timestamp)) / 0.2)
        guard holdProgress >= 1 else { return }
        // Retain the original travel scale so reversing from a frozen full fold still
        // unfolds it. Rebase only the origin; movement during the gap earns nothing.
        travelOrigin = position
        baseProgress = progress
        self.lastPosition = position
        self.missingSince = nil
        recoverySince = nil
        phase = .folding
        clearHold()
    }

    private mutating func held(at timestamp: Double, duration: Double) -> Bool {
        if pendingSince == nil { pendingSince = timestamp }
        holdProgress = min(1, (timestamp - (pendingSince ?? timestamp)) / duration)
        return holdProgress >= 1
    }

    private mutating func clearHold() {
        pendingSince = nil
        holdProgress = 0
    }

    private mutating func cancelGrasp() {
        missingSince = nil
        recoverySince = nil
        phase = .approach
        progress = 0
        baseProgress = 0
        travelOrigin = nil
        arrivalSince = nil
        clearHold()
    }
}
