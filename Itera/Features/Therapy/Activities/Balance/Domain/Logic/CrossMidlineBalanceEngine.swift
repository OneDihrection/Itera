//
//  CrossMidlineBalanceEngine.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import Foundation

/// Body-relative cross-midline scoring. Coordinates use image-height units, so X is
/// aspect-corrected before any distance or angle calculation.
struct CrossMidlineBalanceEngine: BalanceMovementEngine {
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
        let shoulderUnit: TherapyPoint
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
            let shoulderUnit = (averagedRightShoulder - averagedLeftShoulder)
                .scaled(1 / shoulderWidth)
            return Baseline(
                spineUnit: spineUnit,
                lateralUnit: lateralUnit,
                shoulderUnit: shoulderUnit,
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

    private struct TorsoAnchor {
        var point: TherapyPoint
        var timestamp: Double
    }

    private(set) var snapshot = BalanceSnapshot()
    var viewport: TherapyViewport?

    /// The shared bubble radius in normalized image height for the current camera frame.
    private func bubbleRadius(aspect: Double) -> Double {
        sharedBubbleRadius(aspect: aspect, viewport: viewport)
    }
    private var baseline: Baseline?
    private var baselineCapture: BaselineCapture?
    private var generation: UUID?
    private var lastTimestamp: Double?
    /// Credited hold time at the opposite shoulder and back at the start position.
    private var targetHold = InterruptibleHold()
    private var returnHold = InterruptibleHold()
    private var homeWristPositions: [CrossingArm: TherapyPoint] = [:]
    private var compensationLatched = false
    private var compensationCandidateSince: Double?
    private var compensationClearSince: Double?
    private var confirmedCompensation: TrunkCompensation?
    private var kinematics: Kinematics?
    private var jerkSquareSum = 0.0
    private var jerkSampleCount = 0
    private var cachedJoints: [BodyJoint: CachedJoint] = [:]
    private var lastTorsoAnchor: TorsoAnchor?

    private let baselineDuration = 1.0
    private let targetHoldDuration: Double
    private let returnHoldDuration = 5.0
    /// A hold that has begun tolerates a slightly larger circle than the one drawn.
    private let exitRadiusScale = 1.2
    private let leanThresholdDegrees = 18.0
    private let lateralShiftThreshold = 0.40
    private let rotationThreshold = 0.40
    private let compensationEntryDuration = 0.75
    private let compensationExitDuration = 0.50
    /// Keeps the last body overlay drawn through a brief loss, like the finger bubbles.
    private let overlayGracePeriod = InterruptibleHold.trackingGrace
    private let balanceConfidence: Float = 0.20

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
        // A gap earns no hold credit; only a gap beyond the tracking grace clears the holds.
        if delta > InterruptibleHold.trackingGrace {
            clearTransientEvidence()
        } else if delta > 0.3 {
            clearMotionEvidence()
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
            // Often a bystander or brief occlusion: freeze the holds rather than clear them.
            interruptHolds(at: frame.timestamp)
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
                isReturnTarget: false,
                warning: false
            )
            interruptHolds(at: frame.timestamp)
            return
        }

        if !scoringEnabled {
            let target: TherapyPoint? = if baseline == nil {
                nil
            } else {
                switch snapshot.phase {
                case .returning: homeWristPositions[snapshot.activeArm]
                case .complete: nil
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
                progress: snapshot.phase == .returning
                    ? returnProgress
                    : targetProgress,
                isReturnTarget: snapshot.phase == .returning,
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

    mutating func nextSet() {
        guard baseline != nil else {
            restart()
            return
        }

        let arm = snapshot.activeArm
        snapshot.metrics = BalanceMetrics()
        targetHold.reset()
        returnHold.reset()
        jerkSquareSum = 0
        jerkSampleCount = 0
        resetPath()

        // The set ended with a touch, so the first step is the usual return to the start.
        snapshot.activeArm = arm
        snapshot.phase = .returning
        snapshot.instructionKey = "balance.return"
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
            isReturnTarget: false,
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
        if let leftWrist = geometry.leftWrist {
            homeWristPositions[.left] = leftWrist
        }
        if let rightWrist = geometry.rightWrist {
            homeWristPositions[.right] = rightWrist
        }
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
                isReturnTarget: false,
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
            // Compensating is not the requested movement, so the hold restarts.
            targetHold.reset()
            returnHold.reset()
            kinematics = nil
            if snapshot.phase != .returning {
                snapshot.phase = .reaching
            }
            snapshot.instructionKey = "balance.compensationWarning"
        } else {
            compensationLatched = false
            if geometry.isFresh(.neck) || geometry.isFresh(.nose),
                geometry.isFresh(.root) || geometry.isFresh(.leftHip) || geometry.isFresh(.rightHip)
            {
                processTarget(geometry, frame: frame, delta: delta)
            } else {
                interruptHolds(at: frame.timestamp)

                if !targetHold.isHolding && !returnHold.isHolding {
                    snapshot.instructionKey = "balance.holdPosition"
                }
            }
        }

        let target: TherapyPoint? = switch snapshot.phase {
        case .returning: homeWristPositions[snapshot.activeArm]
        case .complete: nil
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
            progress: snapshot.phase == .returning
                ? returnProgress
                : targetProgress,
            isReturnTarget: snapshot.phase == .returning,
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
            handleWristTrackingLoss(at: frame.timestamp)
            return
        }
        guard let target = point(snapshot.activeArm.targetShoulder, in: geometry) else { return }
        let crossed = crossedMidline(wrist: wrist, target: target, geometry: geometry)

        if snapshot.phase == .returning {
            guard let ownShoulder = point(snapshot.activeArm.ownShoulder, in: geometry) else { return }
            let home = homeWristPositions[snapshot.activeArm]
                ?? fallbackHomePosition(for: snapshot.activeArm, geometry: geometry)
            homeWristPositions[snapshot.activeArm] = home
            let returnRadius = bubbleRadius(aspect: frame.aspect)
                * (returnHold.isHolding ? exitRadiusScale : 1)
            let isOnStartingSide = crossedMidline(
                wrist: wrist,
                target: ownShoulder,
                geometry: geometry
            )
            let isInsideStart = (wrist - home).length <= returnRadius

            guard isOnStartingSide, isInsideStart else {
                maintainOrResetReturnHold(at: frame.timestamp)
                return
            }

            returnHold.credit(at: frame.timestamp)
            snapshot.instructionKey = "balance.returnHold"
            if returnProgress >= 1 {
                returnHold.reset()
                snapshot.activeArm = snapshot.armSelection.arm(after: snapshot.activeArm)
                snapshot.phase = .reaching
                snapshot.instructionKey = instruction(for: snapshot.activeArm)
                resetPath()
            }
            return
        }

        if homeWristPositions[snapshot.activeArm] == nil,
            let ownShoulder = point(snapshot.activeArm.ownShoulder, in: geometry),
            crossedMidline(wrist: wrist, target: ownShoulder, geometry: geometry)
        {
            homeWristPositions[snapshot.activeArm] = wrist
        }

        if crossed, delta > 0, delta <= 0.3 {
            snapshot.metrics.midlineDwellTime += delta
        }
        updatePath(position: wrist, time: frame.timestamp, scale: geometry.shoulderWidth)

        let proximity = (wrist - target).length
        let targetRadius = bubbleRadius(aspect: frame.aspect)
            * (targetHold.isHolding ? exitRadiusScale : 1)
        // The visible, body-anchored target is authoritative for contact. It is already
        // centered on the opposite shoulder; requiring a second midline predicate here
        // can reject a wrist that is visibly inside the circle when the torso axis jitters.
        guard proximity <= targetRadius else {
            maintainOrResetTargetHold(at: frame.timestamp)
            return
        }

        targetHold.credit(at: frame.timestamp)
        snapshot.phase = .holding
        snapshot.instructionKey = "balance.hold"
        guard targetProgress >= 1 else { return }

        snapshot.metrics.completedTouches += 1
        targetHold.reset()
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

    /// A lost wrist is a tracking problem, so it gets the longer tracking grace.
    private mutating func handleWristTrackingLoss(at time: Double) {
        if snapshot.phase == .returning {
            maintainOrResetReturnHold(at: time, grace: InterruptibleHold.trackingGrace)
        } else {
            maintainOrResetTargetHold(at: time, grace: InterruptibleHold.trackingGrace)
        }
        if !targetHold.isHolding, !returnHold.isHolding {
            snapshot.instructionKey = "balance.activeWristMissing"
        }
    }

    /// Keeps a hold frozen through a short interruption; clears it once `grace` is exceeded.
    private mutating func maintainOrResetTargetHold(
        at time: Double,
        grace: Double = InterruptibleHold.zoneExitGrace
    ) {
        guard targetHold.interrupt(at: time, grace: grace) else {
            snapshot.phase = .reaching
            snapshot.instructionKey = instruction(for: snapshot.activeArm)
            return
        }
        snapshot.phase = .holding
        snapshot.instructionKey = "balance.hold"
    }

    private mutating func maintainOrResetReturnHold(
        at time: Double,
        grace: Double = InterruptibleHold.zoneExitGrace
    ) {
        guard returnHold.interrupt(at: time, grace: grace) else {
            snapshot.instructionKey = "balance.return"
            return
        }
        snapshot.instructionKey = "balance.returnHold"
    }

    /// Body tracking dropped out (often a bystander or brief occlusion): freeze both holds.
    private mutating func interruptHolds(at time: Double) {
        targetHold.interrupt(at: time, grace: InterruptibleHold.trackingGrace)
        returnHold.interrupt(at: time, grace: InterruptibleHold.trackingGrace)
        clearMotionEvidence()
    }

    /// Velocity and compensation timers are meaningless across a gap; holds are judged separately.
    private mutating func clearMotionEvidence() {
        kinematics = nil
        compensationCandidateSince = nil
        compensationClearSince = nil
    }

    private mutating func clearTransientEvidence() {
        targetHold.reset()
        returnHold.reset()
        kinematics = nil
        compensationCandidateSince = nil
        compensationClearSince = nil
        confirmedCompensation = nil
        compensationLatched = false
        snapshot.compensation = TrunkCompensation()
    }

    private var targetProgress: Double {
        targetHold.progress(duration: targetHoldDuration)
    }

    private var returnProgress: Double {
        returnHold.progress(duration: returnHoldDuration)
    }

    private func fallbackHomePosition(
        for arm: CrossingArm,
        geometry: Geometry
    ) -> TherapyPoint {
        let shoulder = arm == .left ? geometry.leftShoulder : geometry.rightShoulder
        let hip = arm == .left ? geometry.leftHip : geometry.rightHip
        return shoulder + (hip - shoulder).scaled(0.72)
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
        let shoulderAxis = (rightShoulder - leftShoulder).scaled(1 / shoulderWidth)
        let rawLeftHip = resolvedPoint(.leftHip, frame: frame)
        let rawRightHip = resolvedPoint(.rightHip, frame: frame)
        let coherentHips: (left: TherapyPoint, right: TherapyPoint)? = {
            guard let rawLeftHip, let rawRightHip else { return nil }
            let hipAxis = rawRightHip - rawLeftHip
            let hipWidthRatio = hipAxis.length / shoulderWidth
            guard Self.dot(shoulderAxis, hipAxis) > 0,
                (0.25...1.35).contains(hipWidthRatio)
            else { return nil }
            return (rawLeftHip, rawRightHip)
        }()
        let observedRoot = resolvedPoint(.root, frame: frame)
            ?? coherentHips.map { ($0.left + $0.right).scaled(0.5) }
        let shoulderCenter = (leftShoulder + rightShoulder).scaled(0.5)
        let root = observedRoot ?? TherapyPoint(
            x: shoulderCenter.x,
            y: shoulderCenter.y - shoulderWidth * 1.05
        )
        let hipHalfWidth = shoulderWidth * 0.22
        let leftHip = coherentHips?.left ?? root - shoulderAxis.scaled(hipHalfWidth)
        let rightHip = coherentHips?.right ?? root + shoulderAxis.scaled(hipHalfWidth)
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
        if let baseline {
            let widthRatio = geometry.shoulderWidth / baseline.shoulderWidth
            guard (0.35...2.50).contains(widthRatio),
                Self.dot(geometry.spineUnit, baseline.spineUnit) > 0.35,
                Self.dot(shoulderAxis, baseline.shoulderUnit) > 0.20
            else { return nil }
        }
        return geometry
    }

    private var lastOverlayTimestamp: Double?

    private mutating func updateJointCache(from frame: TrackingObservation) {
        guard frame.personCount == 1 else { return }
        let observed = Dictionary(uniqueKeysWithValues: BodyJoint.allCases.compactMap { joint in
            frame.point(joint, minimumConfidence: balanceConfidence).map { (joint, $0) }
        })
        translateOccludedJoints(with: observed, timestamp: frame.timestamp)

        let referenceScale = shoulderScale(from: observed)
        for (joint, current) in observed {
            guard let previous = cachedJoints[joint] else {
                cachedJoints[joint] = CachedJoint(point: current, timestamp: frame.timestamp)
                continue
            }
            let elapsed = frame.timestamp - previous.timestamp
            guard elapsed > 0, elapsed <= overlayGracePeriod else {
                cachedJoints[joint] = CachedJoint(point: current, timestamp: frame.timestamp)
                continue
            }

            let displacement = (current - previous.point).length
            if elapsed <= 0.20,
                displacement / referenceScale > maximumFrameDisplacement(for: joint)
            {
                // A single impossible landmark jump is safer to hold than to draw as a
                // folded torso. The cached point can still follow whole-body translation.
                continue
            }

            let confidence = Double(frame.joints[joint]?.confidence ?? balanceConfidence)
            let weight = adaptiveSmoothingWeight(
                for: joint,
                displacement: displacement,
                elapsed: elapsed,
                scale: referenceScale,
                confidence: confidence
            )
            let smoothed = previous.point.scaled(1 - weight) + current.scaled(weight)
            cachedJoints[joint] = CachedJoint(point: smoothed, timestamp: frame.timestamp)
        }
        cachedJoints = cachedJoints.filter {
            frame.timestamp - $0.value.timestamp <= overlayGracePeriod
        }
    }

    private mutating func translateOccludedJoints(
        with observed: [BodyJoint: TherapyPoint],
        timestamp: Double
    ) {
        guard let anchor = torsoAnchor(from: observed) else { return }
        defer { lastTorsoAnchor = TorsoAnchor(point: anchor, timestamp: timestamp) }
        guard let previous = lastTorsoAnchor else { return }
        let elapsed = timestamp - previous.timestamp
        let translation = anchor - previous.point
        guard elapsed > 0, elapsed <= 0.20, translation.length <= 0.16 else { return }

        for joint in BodyJoint.allCases where observed[joint] == nil {
            guard var cached = cachedJoints[joint],
                timestamp - cached.timestamp <= overlayGracePeriod
            else { continue }
            cached.point = cached.point + translation
            cachedJoints[joint] = cached
        }
    }

    private func torsoAnchor(from points: [BodyJoint: TherapyPoint]) -> TherapyPoint? {
        if let leftShoulder = points[.leftShoulder], let rightShoulder = points[.rightShoulder] {
            return (leftShoulder + rightShoulder).scaled(0.5)
        }
        if let neck = points[.neck], let root = points[.root] {
            return (neck + root).scaled(0.5)
        }
        if let leftHip = points[.leftHip], let rightHip = points[.rightHip] {
            return (leftHip + rightHip).scaled(0.5)
        }
        let anchors = [
            points[.neck], points[.root], points[.leftShoulder], points[.rightShoulder],
            points[.leftHip], points[.rightHip],
        ].compactMap { $0 }
        guard anchors.count >= 2 else { return nil }
        return anchors.reduce(TherapyPoint(x: 0, y: 0), +).scaled(1 / Double(anchors.count))
    }

    private func shoulderScale(from observed: [BodyJoint: TherapyPoint]) -> Double {
        if let left = cachedJoints[.leftShoulder]?.point,
            let right = cachedJoints[.rightShoulder]?.point
        {
            return max(0.08, (right - left).length)
        }
        if let left = observed[.leftShoulder], let right = observed[.rightShoulder] {
            return max(0.08, (right - left).length)
        }
        return 0.25
    }

    private func adaptiveSmoothingWeight(
        for joint: BodyJoint,
        displacement: Double,
        elapsed: Double,
        scale: Double,
        confidence: Double
    ) -> Double {
        let normalizedSpeed = displacement / max(0.001, scale * elapsed)
        let speedResponse = min(1, normalizedSpeed / 2.2)
        let range: ClosedRange<Double> = switch joint {
        case .nose, .neck, .root, .leftShoulder, .rightShoulder, .leftHip, .rightHip:
            0.18...0.72
        case .leftElbow, .rightElbow, .leftWrist, .rightWrist,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle:
            0.30...0.88
        }
        let motionWeight = range.lowerBound
            + (range.upperBound - range.lowerBound) * speedResponse
        let confidenceWeight = 0.65 + min(1, max(0, confidence)) * 0.35
        return min(range.upperBound, max(range.lowerBound, motionWeight * confidenceWeight))
    }

    private func maximumFrameDisplacement(for joint: BodyJoint) -> Double {
        switch joint {
        case .nose, .neck, .root, .leftShoulder, .rightShoulder, .leftHip, .rightHip:
            return 0.70
        case .leftElbow, .rightElbow, .leftWrist, .rightWrist,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle:
            return 1.30
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
        isReturnTarget: Bool,
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
            isReturnTarget: isReturnTarget,
            targetRadius: bubbleRadius(aspect: frame.aspect),
            crossedMidline: crossed,
            targetProgress: progress,
            holdSecondsRemaining: holdSecondsRemaining(
                at: frame.timestamp,
                targetVisible: target != nil,
                isReturnTarget: isReturnTarget
            ),
            compensationWarning: warning
        )
    }

    private func holdSecondsRemaining(
        at time: Double,
        targetVisible: Bool,
        isReturnTarget: Bool
    ) -> Int? {
        guard targetVisible else { return nil }
        let hold = isReturnTarget ? returnHold : targetHold
        let duration = isReturnTarget ? returnHoldDuration : targetHoldDuration

        guard hold.isHolding else { return nil }
        return max(1, Int(ceil(hold.remaining(duration: duration))))
    }

    private static func dot(_ a: TherapyPoint, _ b: TherapyPoint) -> Double {
        a.x * b.x + a.y * b.y
    }

    private static func cross(_ a: TherapyPoint, _ b: TherapyPoint) -> Double {
        a.x * b.y - a.y * b.x
    }
}
