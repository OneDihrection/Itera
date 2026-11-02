//
//  CrossMidlineBalanceEngine.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import Foundation

/// Body-relative cross-midline scoring. Coordinates use image-height units, so X is
/// aspect-corrected before any distance or angle calculation.
struct CrossMidlineBalanceEngine {
    private struct Geometry {
        let neck: TherapyPoint
        let root: TherapyPoint
        let leftShoulder: TherapyPoint
        let rightShoulder: TherapyPoint
        let leftHip: TherapyPoint
        let rightHip: TherapyPoint
        let leftWrist: TherapyPoint?
        let rightWrist: TherapyPoint?
        let rootIsObserved: Bool
        let freshJoints: Set<BodyJoint>

        var spine: TherapyPoint { neck - root }
        var spineLength: Double { spine.length }
        var spineUnit: TherapyPoint { spine.scaled(1 / spineLength) }
        var lateralUnit: TherapyPoint { TherapyPoint(x: spineUnit.y, y: -spineUnit.x) }
        var shoulderWidth: Double { (rightShoulder - leftShoulder).length }
        var normalizedShoulderWidth: Double { shoulderWidth / spineLength }

        func isFresh(_ joint: BodyJoint) -> Bool { freshJoints.contains(joint) }
    }

    private struct Baseline {
        let spineUnit: TherapyPoint
        let lateralUnit: TherapyPoint
        let shoulderWidth: Double
        let normalizedShoulderWidth: Double
        let neckLateralOffset: Double
    }

    private struct BaselineCapture {
        var startedAt: Double
        var anchor: Geometry
        var count = 0.0
        var neck = TherapyPoint(x: 0, y: 0)
        var root = TherapyPoint(x: 0, y: 0)
        var leftShoulder = TherapyPoint(x: 0, y: 0)
        var rightShoulder = TherapyPoint(x: 0, y: 0)

        mutating func append(_ geometry: Geometry) {
            count += 1
            neck = neck + geometry.neck
            root = root + geometry.root
            leftShoulder = leftShoulder + geometry.leftShoulder
            rightShoulder = rightShoulder + geometry.rightShoulder
        }

        func baseline() -> Baseline? {
            guard count > 0 else { return nil }
            let averagedRoot = root.scaled(1 / count)
            let averagedNeck = neck.scaled(1 / count)
            let averagedLeftShoulder = leftShoulder.scaled(1 / count)
            let averagedRightShoulder = rightShoulder.scaled(1 / count)
            let spine = averagedNeck - averagedRoot
            let shoulderWidth = (averagedRightShoulder - averagedLeftShoulder).length
            guard spine.length > 0.08, shoulderWidth > 0.08 else { return nil }
            let spineUnit = spine.scaled(1 / spine.length)
            let lateralUnit = TherapyPoint(x: spineUnit.y, y: -spineUnit.x)
            return Baseline(
                spineUnit: spineUnit,
                lateralUnit: lateralUnit,
                shoulderWidth: shoulderWidth,
                normalizedShoulderWidth: shoulderWidth / spine.length,
                neckLateralOffset: Self.dot(spine, lateralUnit)
            )
        }

        func remainsStable(_ geometry: Geometry) -> Bool {
            let tolerance = anchor.shoulderWidth * 0.30
            let widthChange = abs(geometry.shoulderWidth / anchor.shoulderWidth - 1)
            return (geometry.root - anchor.root).length <= tolerance
                && (geometry.neck - anchor.neck).length <= tolerance
                && widthChange <= 0.35
        }

        private static func dot(_ a: TherapyPoint, _ b: TherapyPoint) -> Double {
            a.x * b.x + a.y * b.y
        }
    }

    private struct Kinematics {
        var time: Double
        var position: TherapyPoint
        var velocity: TherapyPoint?
        var acceleration: TherapyPoint?
    }

    private struct CachedJoint {
        var point: TherapyPoint
        var timestamp: Double
    }

    private(set) var snapshot = BalanceSnapshot()
    private var baseline: Baseline?
    private var baselineCapture: BaselineCapture?
    private var generation: UUID?
    private var lastTimestamp: Double?
    private var targetHoldStartedAt: Double?
    private var compensationLatched = false
    private var compensationCandidateSince: Double?
    private var compensationClearSince: Double?
    private var confirmedCompensation: TrunkCompensation?
    private var kinematics: Kinematics?
    private var jerkSquareSum = 0.0
    private var jerkSampleCount = 0
    private var cachedJoints: [BodyJoint: CachedJoint] = [:]

    private let baselineDuration = 1.0
    private let targetHoldDuration: Double
    private let leanThresholdDegrees = 18.0
    private let lateralShiftThreshold = 0.40
    private let rotationThreshold = 0.40
    private let compensationEntryDuration = 0.75
    private let compensationExitDuration = 0.50
    private let overlayGracePeriod = 1.25
    private let balanceConfidence: Float = 0.25

    init(
        goal: Int = 6,
        holdDuration: Double = 10,
        armSelection: BalanceArmSelection = .both
    ) {
        snapshot.goal = max(2, goal)
        targetHoldDuration = min(20, max(3, holdDuration))
        snapshot.holdDuration = targetHoldDuration
        snapshot.armSelection = armSelection
        snapshot.activeArm = armSelection.initialArm
    }

    mutating func consume(_ frame: TrackingObservation, scoringEnabled: Bool = true) {
        guard frame.timestamp.isFinite,
            lastTimestamp.map({ frame.timestamp > $0 }) ?? true
        else {
            clearTransientEvidence()
            return
        }

        if let generation, generation != frame.generation {
            invalidateCalibration()
        }
        generation = frame.generation

        let delta = lastTimestamp.map { frame.timestamp - $0 } ?? 0
        lastTimestamp = frame.timestamp
        if delta > 0.3 {
            clearTransientEvidence()
        }

        updateJointCache(from: frame)
        guard let geometry = geometry(from: frame) else {
            snapshot.phase = baseline == nil ? .findingBody : snapshot.phase
            snapshot.instructionKey = "balance.tracking"
            if let previous = snapshot.overlay,
                frame.timestamp - (lastOverlayTimestamp ?? frame.timestamp) <= overlayGracePeriod
            {
                snapshot.overlay = previous
            } else {
                snapshot.overlay = nil
            }
            clearTransientEvidence()
            return
        }

        guard geometry.rootIsObserved else {
            snapshot.phase = baseline == nil ? .findingBody : snapshot.phase
            snapshot.instructionKey = "balance.pelvisMissing"
            snapshot.overlay = overlay(
                geometry: geometry,
                frame: frame,
                target: nil,
                crossed: false,
                progress: 0,
                warning: false
            )
            clearTransientEvidence()
            return
        }

        if !scoringEnabled {
            let target: TherapyPoint? = if baseline == nil {
                nil
            } else {
                switch snapshot.phase {
                case .returning, .complete: nil
                default: point(snapshot.activeArm.targetShoulder, in: geometry)
                }
            }
            let wrist = point(snapshot.activeArm.wrist, in: geometry)
            let crossed = wrist.map {
                crossedMidline(wrist: $0, target: target ?? geometry.neck, geometry: geometry)
            } ?? false
            snapshot.overlay = overlay(
                geometry: geometry,
                frame: frame,
                target: target,
                crossed: crossed,
                progress: targetProgress(at: frame.timestamp),
                warning: snapshot.compensation.isCompensating
            )
            lastOverlayTimestamp = frame.timestamp
            clearTransientEvidence()
            return
        }

        if baseline == nil {
            captureBaseline(geometry, frame: frame)
            return
        }

        updateActiveMovement(geometry, frame: frame, delta: delta)
    }

    mutating func invalidateCalibration() {
        baseline = nil
        baselineCapture = nil
        snapshot.phase = .findingBody
        snapshot.instructionKey = "balance.tracking"
        snapshot.calibrationProgress = 0
        snapshot.overlay = nil
        cachedJoints.removeAll()
        lastOverlayTimestamp = nil
        clearTransientEvidence()
    }

    mutating func restart() {
        self = CrossMidlineBalanceEngine(
            goal: snapshot.goal,
            holdDuration: snapshot.holdDuration,
            armSelection: snapshot.armSelection
        )
    }

    private mutating func captureBaseline(_ geometry: Geometry, frame: TrackingObservation) {
        snapshot.phase = .calibrating
        snapshot.instructionKey = "balance.calibrating"
        snapshot.compensation = TrunkCompensation()
        snapshot.overlay = overlay(
            geometry: geometry,
            frame: frame,
            target: nil,
            crossed: false,
            progress: snapshot.calibrationProgress,
            warning: false
        )
        lastOverlayTimestamp = frame.timestamp

        if baselineCapture?.remainsStable(geometry) != true {
            baselineCapture = BaselineCapture(startedAt: frame.timestamp, anchor: geometry)
        }
        baselineCapture?.append(geometry)
        let elapsed = frame.timestamp - (baselineCapture?.startedAt ?? frame.timestamp)
        snapshot.calibrationProgress = min(1, elapsed / baselineDuration)

        guard elapsed >= baselineDuration, let captured = baselineCapture?.baseline() else {
            return
        }
        baseline = captured
        baselineCapture = nil
        snapshot.phase = .reaching
        snapshot.instructionKey = instruction(for: snapshot.activeArm)
        snapshot.calibrationProgress = 1
    }

    private mutating func updateActiveMovement(
        _ geometry: Geometry,
        frame: TrackingObservation,
        delta: Double
    ) {
        if snapshot.phase == .complete {
            snapshot.overlay = overlay(
                geometry: geometry,
                frame: frame,
                target: nil,
                crossed: false,
                progress: 0,
                warning: false
            )
            lastOverlayTimestamp = frame.timestamp
            return
        }
        guard let baseline else { return }
        let rawCompensation = compensation(for: geometry, baseline: baseline)
        let compensation = stabilizedCompensation(
            rawCompensation,
            timestamp: frame.timestamp
        )
        snapshot.compensation = compensation

        if compensation.isCompensating {
            if !compensationLatched {
                snapshot.metrics.compensationEventsCount += 1
                compensationLatched = true
            }
            targetHoldStartedAt = nil
            kinematics = nil
            snapshot.phase = .reaching
            snapshot.instructionKey = "balance.compensationWarning"
        } else {
            compensationLatched = false
            if geometry.isFresh(.neck) || geometry.isFresh(.nose),
                geometry.isFresh(.root) || geometry.isFresh(.leftHip) || geometry.isFresh(.rightHip)
            {
                processTarget(geometry, frame: frame, delta: delta)
            } else {
                targetHoldStartedAt = nil
                snapshot.instructionKey = "balance.holdPosition"
            }
        }

        let target: TherapyPoint? = switch snapshot.phase {
        case .returning, .complete: nil
        default: point(snapshot.activeArm.targetShoulder, in: geometry)
        }
        let wrist = point(snapshot.activeArm.wrist, in: geometry)
        let crossed = wrist.map {
            crossedMidline(wrist: $0, target: target ?? geometry.neck, geometry: geometry)
        } ?? false
        snapshot.overlay = overlay(
            geometry: geometry,
            frame: frame,
            target: target,
            crossed: crossed,
            progress: targetProgress(at: frame.timestamp),
            warning: compensation.isCompensating
        )
        lastOverlayTimestamp = frame.timestamp
    }

    private mutating func processTarget(
        _ geometry: Geometry,
        frame: TrackingObservation,
        delta: Double
    ) {
        guard snapshot.phase != .complete else { return }
        guard geometry.isFresh(snapshot.activeArm.wrist),
            let wrist = point(snapshot.activeArm.wrist, in: geometry)
        else {
            targetHoldStartedAt = nil
            snapshot.instructionKey = "balance.activeWristMissing"
            return
        }
        guard let target = point(snapshot.activeArm.targetShoulder, in: geometry) else { return }
        let crossed = crossedMidline(wrist: wrist, target: target, geometry: geometry)

        if snapshot.phase == .returning {
            guard let ownShoulder = point(snapshot.activeArm.ownShoulder, in: geometry) else { return }
            if crossedMidline(wrist: wrist, target: ownShoulder, geometry: geometry) {
                snapshot.activeArm = snapshot.armSelection.arm(after: snapshot.activeArm)
                snapshot.phase = .reaching
                snapshot.instructionKey = instruction(for: snapshot.activeArm)
                resetPath()
            } else {
                snapshot.instructionKey = "balance.return"
            }
            return
        }

        if crossed, delta > 0, delta <= 0.3 {
            snapshot.metrics.midlineDwellTime += delta
        }
        updatePath(position: wrist, time: frame.timestamp, scale: geometry.shoulderWidth)

        let proximity = (wrist - target).length
        let targetRadius = max(0.045, geometry.shoulderWidth * 0.28)
        guard crossed, proximity <= targetRadius else {
            targetHoldStartedAt = nil
            snapshot.phase = .reaching
            snapshot.instructionKey = instruction(for: snapshot.activeArm)
            return
        }

        if targetHoldStartedAt == nil { targetHoldStartedAt = frame.timestamp }
        snapshot.phase = .holding
        snapshot.instructionKey = "balance.hold"
        guard targetProgress(at: frame.timestamp) >= 1 else { return }

        snapshot.metrics.completedTouches += 1
        targetHoldStartedAt = nil
        resetPath()
        if snapshot.metrics.completedTouches >= snapshot.goal {
            snapshot.phase = .complete
            snapshot.instructionKey = "balance.complete"
        } else {
            snapshot.phase = .returning
            snapshot.instructionKey = "balance.return"
        }
    }

    private func compensation(for geometry: Geometry, baseline: Baseline) -> TrunkCompensation {
        let currentSpine = geometry.spineUnit
        let signedLean = atan2(
            Self.cross(baseline.spineUnit, currentSpine),
            Self.dot(baseline.spineUnit, currentSpine)
        ) * 180 / .pi
        let currentLateralOffset = Self.dot(geometry.spine, baseline.lateralUnit)
        let lateralShift = abs(currentLateralOffset - baseline.neckLateralOffset) / baseline.shoulderWidth
        let rotationLoss = max(
            0,
            1 - geometry.normalizedShoulderWidth / baseline.normalizedShoulderWidth
        )

        var reasons: Set<TrunkCompensation.Reason> = []
        if abs(signedLean) > leanThresholdDegrees { reasons.insert(.lateralLean) }
        if lateralShift > lateralShiftThreshold { reasons.insert(.lateralShift) }
        if rotationLoss > rotationThreshold { reasons.insert(.shoulderRotation) }

        return TrunkCompensation(
            leanDegrees: signedLean,
            lateralShiftRatio: lateralShift,
            shoulderRotationRatio: rotationLoss,
            index: max(
                abs(signedLean) / leanThresholdDegrees,
                lateralShift / lateralShiftThreshold,
                rotationLoss / rotationThreshold
            ),
            reasons: reasons
        )
    }

    /// Rejects brief Vision landmark spikes before they can cancel a long patient hold.
    private mutating func stabilizedCompensation(
        _ raw: TrunkCompensation,
        timestamp: Double
    ) -> TrunkCompensation {
        if raw.isCompensating {
            compensationClearSince = nil

            if confirmedCompensation != nil {
                confirmedCompensation = raw
                return raw
            }

            if compensationCandidateSince == nil {
                compensationCandidateSince = timestamp
            }
            guard timestamp - (compensationCandidateSince ?? timestamp)
                >= compensationEntryDuration
            else {
                return TrunkCompensation(
                    leanDegrees: raw.leanDegrees,
                    lateralShiftRatio: raw.lateralShiftRatio,
                    shoulderRotationRatio: raw.shoulderRotationRatio,
                    index: raw.index
                )
            }

            compensationCandidateSince = nil
            confirmedCompensation = raw
            return raw
        }

        compensationCandidateSince = nil
        guard let confirmedCompensation else {
            compensationClearSince = nil
            return raw
        }

        if compensationClearSince == nil {
            compensationClearSince = timestamp
        }
        guard timestamp - (compensationClearSince ?? timestamp)
            >= compensationExitDuration
        else {
            return confirmedCompensation
        }

        self.confirmedCompensation = nil
        compensationClearSince = nil
        return raw
    }

    private func crossedMidline(
        wrist: TherapyPoint,
        target: TherapyPoint,
        geometry: Geometry
    ) -> Bool {
        let axis = geometry.spineUnit
        let wristSide = Self.cross(axis, wrist - geometry.root)
        let targetSide = Self.cross(axis, target - geometry.root)
        let margin = geometry.shoulderWidth * 0.05
        return wristSide * targetSide > 0 && abs(wristSide) >= margin
    }

    private mutating func updatePath(position: TherapyPoint, time: Double, scale: Double) {
        defer { snapshot.metrics.pathSmoothness = smoothness }
        guard let previous = kinematics else {
            kinematics = Kinematics(time: time, position: position)
            return
        }
        let delta = time - previous.time
        guard delta >= 0.03, delta <= 0.2, scale > 0 else {
            kinematics = Kinematics(time: time, position: position)
            return
        }

        let velocity = (position - previous.position).scaled(1 / delta)
        guard let previousVelocity = previous.velocity else {
            kinematics = Kinematics(time: time, position: position, velocity: velocity)
            return
        }
        let acceleration = (velocity - previousVelocity).scaled(1 / delta)
        if let previousAcceleration = previous.acceleration {
            let jerk = (acceleration - previousAcceleration).scaled(1 / delta / scale).length
            jerkSquareSum += jerk * jerk
            jerkSampleCount += 1
        }
        kinematics = Kinematics(
            time: time,
            position: position,
            velocity: velocity,
            acceleration: acceleration
        )
    }

    private var smoothness: Double {
        guard jerkSampleCount > 0 else { return 1 }
        let rootMeanSquareJerk = sqrt(jerkSquareSum / Double(jerkSampleCount))
        return 1 / (1 + rootMeanSquareJerk * 0.002)
    }

    private mutating func resetPath() {
        kinematics = nil
    }

    private mutating func clearTransientEvidence() {
        targetHoldStartedAt = nil
        kinematics = nil
        compensationCandidateSince = nil
        compensationClearSince = nil
        confirmedCompensation = nil
        compensationLatched = false
        snapshot.compensation = TrunkCompensation()
    }

    private func targetProgress(at time: Double) -> Double {
        guard let targetHoldStartedAt else { return 0 }
        return min(1, max(0, (time - targetHoldStartedAt) / targetHoldDuration))
    }

    private func instruction(for arm: CrossingArm) -> String {
        arm == .right ? "balance.reachRight" : "balance.reachLeft"
    }

    private func point(_ joint: BodyJoint, in geometry: Geometry) -> TherapyPoint? {
        switch joint {
        case .leftShoulder: return geometry.leftShoulder
        case .rightShoulder: return geometry.rightShoulder
        case .leftWrist: return geometry.leftWrist
        case .rightWrist: return geometry.rightWrist
        default: return nil
        }
    }

    private mutating func geometry(from frame: TrackingObservation) -> Geometry? {
        guard frame.personCount == 1,
            let neck = resolvedPoint(.neck, frame: frame) ?? resolvedPoint(.nose, frame: frame),
            let leftShoulder = resolvedPoint(.leftShoulder, frame: frame),
            let rightShoulder = resolvedPoint(.rightShoulder, frame: frame)
        else { return nil }

        let shoulderWidth = (rightShoulder - leftShoulder).length
        guard shoulderWidth > 0.08 else { return nil }
        let observedLeftHip = resolvedPoint(.leftHip, frame: frame)
        let observedRightHip = resolvedPoint(.rightHip, frame: frame)
        let observedRoot = resolvedPoint(.root, frame: frame) ?? {
            guard let observedLeftHip, let observedRightHip else { return nil }
            return (observedLeftHip + observedRightHip).scaled(0.5)
        }()
        let shoulderCenter = (leftShoulder + rightShoulder).scaled(0.5)
        let root = observedRoot ?? TherapyPoint(
            x: shoulderCenter.x,
            y: shoulderCenter.y - shoulderWidth * 1.05
        )
        let shoulderAxis = (rightShoulder - leftShoulder).scaled(1 / shoulderWidth)
        let hipHalfWidth = shoulderWidth * 0.22
        let leftHip = observedLeftHip ?? root - shoulderAxis.scaled(hipHalfWidth)
        let rightHip = observedRightHip ?? root + shoulderAxis.scaled(hipHalfWidth)
        let geometry = Geometry(
            neck: neck,
            root: root,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: leftHip,
            rightHip: rightHip,
            leftWrist: resolvedPoint(.leftWrist, frame: frame),
            rightWrist: resolvedPoint(.rightWrist, frame: frame),
            rootIsObserved: observedRoot != nil,
            freshJoints: Set(BodyJoint.allCases.filter {
                frame.point($0, minimumConfidence: balanceConfidence) != nil
            })
        )
        guard geometry.spineLength > 0.08,
            geometry.shoulderWidth > 0.08
        else { return nil }
        return geometry
    }

    private var lastOverlayTimestamp: Double?

    private mutating func updateJointCache(from frame: TrackingObservation) {
        guard frame.personCount == 1 else { return }
        for joint in BodyJoint.allCases {
            guard let current = frame.point(joint, minimumConfidence: balanceConfidence) else { continue }
            let smoothed: TherapyPoint
            if let previous = cachedJoints[joint],
                frame.timestamp - previous.timestamp <= 0.25,
                (current - previous.point).length <= 0.35
            {
                let currentWeight = smoothingWeight(for: joint)
                smoothed = previous.point.scaled(1 - currentWeight)
                    + current.scaled(currentWeight)
            } else {
                smoothed = current
            }
            cachedJoints[joint] = CachedJoint(point: smoothed, timestamp: frame.timestamp)
        }
        cachedJoints = cachedJoints.filter {
            frame.timestamp - $0.value.timestamp <= overlayGracePeriod
        }
    }

    private func smoothingWeight(for joint: BodyJoint) -> Double {
        switch joint {
        case .nose, .neck, .root, .leftShoulder, .rightShoulder, .leftHip, .rightHip:
            return 0.45
        case .leftElbow, .rightElbow, .leftWrist, .rightWrist:
            return 0.70
        }
    }

    private func resolvedPoint(_ joint: BodyJoint, frame: TrackingObservation) -> TherapyPoint? {
        guard let cached = cachedJoints[joint],
            frame.timestamp - cached.timestamp <= overlayGracePeriod
        else { return nil }
        return cached.point
    }

    private func overlay(
        geometry: Geometry,
        frame: TrackingObservation,
        target: TherapyPoint?,
        crossed: Bool,
        progress: Double,
        warning: Bool
    ) -> BalanceOverlay {
        BalanceOverlay(
            aspect: frame.aspect,
            midlineBase: geometry.root,
            midlineTop: geometry.neck,
            leftShoulder: geometry.leftShoulder,
            rightShoulder: geometry.rightShoulder,
            leftHip: geometry.leftHip,
            rightHip: geometry.rightHip,
            wrist: point(snapshot.activeArm.wrist, in: geometry),
            target: target,
            targetRadius: max(0.045, geometry.shoulderWidth * 0.28),
            crossedMidline: crossed,
            targetProgress: progress,
            holdSecondsRemaining: target == nil ? nil : holdSecondsRemaining(at: frame.timestamp),
            compensationWarning: warning
        )
    }

    private func holdSecondsRemaining(at time: Double) -> Int? {
        guard let targetHoldStartedAt else { return nil }
        let remaining = max(0, targetHoldDuration - (time - targetHoldStartedAt))
        return max(1, Int(ceil(remaining)))
    }

    private static func dot(_ a: TherapyPoint, _ b: TherapyPoint) -> Double {
        a.x * b.x + a.y * b.y
    }

    private static func cross(_ a: TherapyPoint, _ b: TherapyPoint) -> Double {
        a.x * b.y - a.y * b.x
    }
}
