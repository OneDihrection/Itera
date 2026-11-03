//
//  ExternalRotationEngine.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import Foundation

/// Shoulder external or internal rotation with the elbow at the side, seen from the front.
///
/// With the elbow bent about 90° beside the body, the forearm points toward the camera. External
/// rotation turns it outward, swinging the wrist away from the body in the image; internal rotation
/// turns it inward toward the belly. The sideways distance of the wrist from the elbow, along the
/// line from the body center to the working shoulder, gives an estimated rotation angle:
///
/// ```text
/// outward = normalize(workingShoulder − otherShoulder)
/// lateral = sign · (dot(wrist − elbow, outward) − neutralLateral)   // sign is −1 for inward
/// angle   = asin(clamp(lateral / (0.9 · upperArm₀), −1, 1))
/// ```
///
/// The 0.9 factor stands in for the forearm length, which cannot be measured while the forearm
/// points at the camera, so the angle is an estimate and not a clinical measurement and is only
/// displayed. Positions are measured, not computed: calibration records where the wrist rests
/// (start) and where it is held at the patient's comfortable end (target), each as an offset from
/// the elbow in the body's outward/across axes. The blue circle sits at the start offset and the
/// orange circle at the target offset, so they appear exactly where the patient's own wrist was.
/// A hold in the orange circle counts one rotation; the patient then returns to the blue one.
///
/// Posture checks flag the usual compensations: the elbow drifting away from the body, and the same
/// trunk lean, shift, and shoulder turn used by Balancing.
struct ExternalRotationEngine: BalanceMovementEngine {
    private struct Geometry {
        let neck: TherapyPoint
        let root: TherapyPoint
        let leftShoulder: TherapyPoint
        let rightShoulder: TherapyPoint
        let shoulder: TherapyPoint
        let elbow: TherapyPoint
        let wrist: TherapyPoint
        let otherShoulder: TherapyPoint

        var spine: TherapyPoint { neck - root }
        var spineUnit: TherapyPoint { spine.scaled(1 / spine.length) }
        var lateralUnit: TherapyPoint { TherapyPoint(x: spineUnit.y, y: -spineUnit.x) }
        var shoulderWidth: Double { (rightShoulder - leftShoulder).length }
        var normalizedShoulderWidth: Double { shoulderWidth / spine.length }
        var upperArm: Double { (elbow - shoulder).length }
        /// Perpendicular to `outward`, so offsets from the elbow keep their meaning if the body turns.
        var across: TherapyPoint { TherapyPoint(x: -outward.y, y: outward.x) }
        func local(_ vector: TherapyPoint) -> TherapyPoint {
            TherapyPoint(x: vector.dotProduct(outward), y: vector.dotProduct(across))
        }
        func world(_ local: TherapyPoint) -> TherapyPoint {
            outward.scaled(local.x) + across.scaled(local.y)
        }
        var outward: TherapyPoint {
            let direction = shoulder - otherShoulder
            return direction.scaled(1 / max(direction.length, 0.0001))
        }
    }

    private struct TorsoBaseline {
        let spineUnit: TherapyPoint
        let lateralUnit: TherapyPoint
        let shoulderUnit: TherapyPoint
        let shoulderWidth: Double
        let normalizedShoulderWidth: Double
        let neckLateralOffset: Double
    }

    /// The working arm's resting pose: the wrist relative to the elbow, and how far the elbow
    /// sits from the shoulder line, both measured at calibration.
    private struct Neutral {
        let upperArm: Double
        /// Wrist offset from the elbow, in the outward/across axes.
        let wrist: TherapyPoint
        let elbowOut: Double
    }

    private struct Capture {
        let startedAt: Double
        let anchor: Geometry
        var count = 0.0
        var neck = TherapyPoint(x: 0, y: 0)
        var root = TherapyPoint(x: 0, y: 0)
        var leftShoulder = TherapyPoint(x: 0, y: 0)
        var rightShoulder = TherapyPoint(x: 0, y: 0)
        var elbow = TherapyPoint(x: 0, y: 0)
        var wrist = TherapyPoint(x: 0, y: 0)
        var localWrist = TherapyPoint(x: 0, y: 0)
        var elbowOut = 0.0
        var upperArm = 0.0

        mutating func append(_ geometry: Geometry) {
            count += 1
            neck = neck + geometry.neck
            root = root + geometry.root
            leftShoulder = leftShoulder + geometry.leftShoulder
            rightShoulder = rightShoulder + geometry.rightShoulder
            elbow = elbow + geometry.elbow
            wrist = wrist + geometry.wrist
            localWrist = localWrist + geometry.local(geometry.wrist - geometry.elbow)
            elbowOut += (geometry.elbow - geometry.shoulder).dotProduct(geometry.outward)
            upperArm += geometry.upperArm
        }

        func remainsStable(_ geometry: Geometry) -> Bool {
            let tolerance = anchor.shoulderWidth * 0.30
            let widthChange = abs(geometry.shoulderWidth / anchor.shoulderWidth - 1)
            return (geometry.root - anchor.root).length <= tolerance
                && (geometry.neck - anchor.neck).length <= tolerance
                && (geometry.elbow - anchor.elbow).length <= tolerance
                && (geometry.wrist - anchor.wrist).length <= tolerance
                && widthChange <= 0.35
        }

        func torso() -> TorsoBaseline? {
            guard count > 0 else { return nil }
            let rightShoulder = rightShoulder.scaled(1 / count)
            let leftShoulder = leftShoulder.scaled(1 / count)
            let spine = neck.scaled(1 / count) - root.scaled(1 / count)
            let width = (rightShoulder - leftShoulder).length
            guard spine.length > 0.08, width > 0.08 else { return nil }
            let unit = spine.scaled(1 / spine.length)
            let lateral = TherapyPoint(x: unit.y, y: -unit.x)
            return TorsoBaseline(
                spineUnit: unit,
                lateralUnit: lateral,
                shoulderUnit: (rightShoulder - leftShoulder).scaled(1 / width),
                shoulderWidth: width,
                normalizedShoulderWidth: width / spine.length,
                neckLateralOffset: spine.dotProduct(lateral)
            )
        }

        func neutral() -> Neutral? {
            guard count > 0 else { return nil }
            let upperArm = upperArm / count
            guard upperArm > 0.04 else { return nil }
            return Neutral(
                upperArm: upperArm,
                wrist: localWrist.scaled(1 / count),
                elbowOut: elbowOut / count
            )
        }
    }

    private struct Kinematics {
        var time: Double
        var position: TherapyPoint
        var velocity: TherapyPoint?
        var acceleration: TherapyPoint?
    }

    private(set) var snapshot = BalanceSnapshot()
    private var smoother = MovementLandmarkSmoother()
    private var torso: TorsoBaseline?
    private var neutrals: [CrossingArm: Neutral] = [:]
    private var capture: Capture?
    private var lastTimestamp: Double?
    private var generation: UUID?
    private var targetHoldStartedAt: Double?
    private var targetOutsideSince: Double?
    private var returnHoldStartedAt: Double?
    private var returnOutsideSince: Double?
    private var compensationLatched = false
    private var compensationCandidateSince: Double?
    private var compensationClearSince: Double?
    private var confirmedCompensation: TrunkCompensation?
    private var kinematics: Kinematics?
    private var jerkSquareSum = 0.0
    private var jerkSampleCount = 0
    private var lastOverlayTimestamp: Double?
    /// Each arm's own comfortable rotation, captured at calibration, in degrees.
    private var targets: [CrossingArm: Double] = [:]
    /// Where each arm's wrist was held at its comfortable end, as an offset from the elbow.
    private var ends: [CrossingArm: TherapyPoint] = [:]
    private var rangeOffsetSum = TherapyPoint(x: 0, y: 0)
    private var rangeAnchor: Double?
    private var rangeStartedAt = 0.0
    private var rangeSum = 0.0
    private var rangeCount = 0.0

    private let calibrationDuration = 1.0
    private let targetHoldDuration: Double
    private let returnHoldDuration = 3.0
    private let direction: RotationDirection
    private let forearmRatio = 0.9
    /// A turn smaller than this is treated as not turning yet.
    private let minimumTargetAngle = 12.0
    private let maximumTargetAngle = 90.0
    private let rangeHoldDuration = 2.0
    private let rangeTolerance = 6.0
    private let trackingGracePeriod = 0.40
    private let targetRadiusRatio = 0.28
    private let exitRadiusScale = 1.25
    private let elbowAwayThreshold = 0.35
    private let leanThresholdDegrees = 18.0
    private let lateralShiftThreshold = 0.40
    private let rotationThreshold = 0.40
    private let compensationEntryDuration = 0.75
    private let compensationExitDuration = 0.50
    private let minimumConfidence: Float = 0.3

    init(
        goal: Int = 6,
        holdDuration: Double = 10,
        armSelection: BalanceArmSelection = .both,
        direction: RotationDirection = .outward
    ) {
        self.direction = direction
        snapshot.goal = max(2, goal)
        targetHoldDuration = min(20, max(3, holdDuration))
        snapshot.holdDuration = targetHoldDuration
        snapshot.armSelection = armSelection
        snapshot.activeArm = armSelection.initialArm
        snapshot.instructionKey = "rotation.tracking"
    }

    // MARK: - Frames

    mutating func consume(_ frame: TrackingObservation, scoringEnabled: Bool = true) {
        guard frame.timestamp.isFinite, lastTimestamp.map({ frame.timestamp > $0 }) ?? true else {
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
        let filtered = smoother.consume(frame)
        guard let geometry = geometry(from: filtered) else {
            snapshot.phase = torso == nil ? .findingBody : snapshot.phase
            snapshot.instructionKey = "rotation.tracking"
            if frame.timestamp - (lastOverlayTimestamp ?? frame.timestamp) > 1.25 {
                snapshot.overlay = nil
            }
            clearTransientEvidence()
            return
        }
        if !scoringEnabled {
            publishOverlay(geometry, frame: frame)
            clearTransientEvidence()
            return
        }
        guard let torso, let neutral = neutrals[snapshot.activeArm] else {
            calibrate(geometry, frame: frame)
            return
        }
        guard targets[snapshot.activeArm] != nil else {
            calibrateRange(geometry, frame: frame, neutral: neutral)
            return
        }
        update(geometry, frame: frame, torso: torso, neutral: neutral, delta: delta)
    }

    mutating func invalidateCalibration() {
        torso = nil
        capture = nil
        neutrals.removeAll()
        targets.removeAll()
        ends.removeAll()
        resetRange()
        smoother.reset()
        snapshot.phase = .findingBody
        snapshot.instructionKey = "rotation.tracking"
        snapshot.calibrationProgress = 0
        snapshot.overlay = nil
        lastOverlayTimestamp = nil
        clearTransientEvidence()
    }

    mutating func restart() {
        self = ExternalRotationEngine(
            goal: snapshot.goal,
            holdDuration: snapshot.holdDuration,
            armSelection: snapshot.armSelection,
            direction: direction
        )
    }

    // MARK: - Calibration

    private mutating func calibrate(_ geometry: Geometry, frame: TrackingObservation) {
        snapshot.phase = .calibrating
        snapshot.compensation = TrunkCompensation()
        // The upper arm should hang beside the body, roughly along the spine, for a valid rest pose.
        let hang = (geometry.elbow - geometry.shoulder).scaled(1 / max(geometry.upperArm, 0.0001))
        let alongBody = -hang.dotProduct(geometry.spineUnit)
        guard alongBody > 0.65 else {
            capture = nil
            snapshot.calibrationProgress = 0
            snapshot.instructionKey = "rotation.elbowAtSide"
            publishOverlay(geometry, frame: frame)
            return
        }
        snapshot.instructionKey = "rotation.calibrating"
        publishOverlay(geometry, frame: frame)
        if capture?.remainsStable(geometry) != true {
            capture = Capture(startedAt: frame.timestamp, anchor: geometry)
        }
        capture?.append(geometry)
        let elapsed = frame.timestamp - (capture?.startedAt ?? frame.timestamp)
        snapshot.calibrationProgress = min(1, elapsed / calibrationDuration)
        guard elapsed >= calibrationDuration, let captured = capture,
              let neutral = captured.neutral()
        else {
            return
        }
        if torso == nil {
            torso = captured.torso()
        }
        guard torso != nil else {
            capture = nil
            return
        }
        neutrals[snapshot.activeArm] = neutral
        capture = nil
        beginRangeCalibration()
    }

    private mutating func beginRangeCalibration() {
        resetRange()
        snapshot.phase = .calibratingRange
        snapshot.instructionKey = "rotation.calibrateRange"
        snapshot.calibrationProgress = 0
        snapshot.targetAngle = 0
    }

    private mutating func resetRange() {
        rangeAnchor = nil
        rangeSum = 0
        rangeCount = 0
        rangeOffsetSum = TherapyPoint(x: 0, y: 0)
    }

    /// The patient turns as far as is comfortable and holds still; that held angle becomes the
    /// target for this arm, so no fixed angle is imposed.
    private mutating func calibrateRange(_ geometry: Geometry, frame: TrackingObservation, neutral: Neutral) {
        snapshot.phase = .calibratingRange
        snapshot.compensation = TrunkCompensation()
        snapshot.instructionKey = "rotation.calibrateRange"
        let angle = rotationAngle(geometry, neutral: neutral)
        let offset = geometry.local(geometry.wrist - geometry.elbow)
        snapshot.rotationDegrees = max(0, angle)
        publishOverlay(geometry, frame: frame, neutral: neutral)
        guard angle >= minimumTargetAngle else {
            resetRange()
            snapshot.calibrationProgress = 0
            return
        }
        if let anchor = rangeAnchor, abs(angle - anchor) <= rangeTolerance {
            rangeSum += angle
            rangeCount += 1
            rangeOffsetSum = rangeOffsetSum + offset
        } else {
            rangeAnchor = angle
            rangeStartedAt = frame.timestamp
            rangeSum = angle
            rangeCount = 1
            rangeOffsetSum = offset
        }
        let elapsed = frame.timestamp - rangeStartedAt
        snapshot.calibrationProgress = min(1, elapsed / rangeHoldDuration)
        guard elapsed >= rangeHoldDuration else {
            return
        }
        let held = min(maximumTargetAngle, rangeSum / rangeCount)
        targets[snapshot.activeArm] = held
        ends[snapshot.activeArm] = rangeOffsetSum.scaled(1 / rangeCount)
        snapshot.targetAngle = Int(held.rounded())
        snapshot.calibrationProgress = 1
        resetRange()
        // The patient is still at the target; they return to the start before the first rotation.
        snapshot.phase = .returning
        snapshot.instructionKey = "rotation.return"
    }

    /// Estimated forearm rotation in degrees, positive in this exercise's direction.
    private func rotationAngle(_ geometry: Geometry, neutral: Neutral) -> Double {
        let lateral = sign * (geometry.local(geometry.wrist - geometry.elbow).x - neutral.wrist.x)
        let reference = neutral.upperArm * forearmRatio
        return asin(max(-1, min(1, lateral / reference))) * 180 / .pi
    }

    // MARK: - Movement

    private mutating func update(
        _ geometry: Geometry,
        frame: TrackingObservation,
        torso: TorsoBaseline,
        neutral: Neutral,
        delta: Double
    ) {
        if snapshot.phase == .complete {
            publishOverlay(geometry, frame: frame)
            return
        }
        let angle = rotationAngle(geometry, neutral: neutral)
        snapshot.rotationDegrees = max(0, angle)
        snapshot.metrics.peakRotation = max(snapshot.metrics.peakRotation, snapshot.rotationDegrees)

        let compensation = stabilized(
            rawCompensation(geometry, torso: torso, neutral: neutral),
            at: frame.timestamp
        )
        snapshot.compensation = compensation
        if compensation.isCompensating {
            if !compensationLatched {
                snapshot.metrics.compensationEventsCount += 1
                compensationLatched = true
            }
            targetHoldStartedAt = nil
            targetOutsideSince = nil
            returnHoldStartedAt = nil
            returnOutsideSince = nil
            kinematics = nil
            if snapshot.phase != .returning {
                snapshot.phase = .reaching
            }
            snapshot.instructionKey = "rotation.compensationWarning"
        } else {
            compensationLatched = false
            process(geometry, frame: frame, neutral: neutral, delta: delta)
        }
        publishOverlay(geometry, frame: frame, neutral: neutral)
    }

    /// +1 when the wrist travels away from the body, −1 when it travels toward it.
    private var sign: Double { direction == .outward ? 1 : -1 }

    /// Where the wrist was held at the patient's own comfortable end.
    private func targetCenter(_ geometry: Geometry, neutral: Neutral) -> TherapyPoint {
        geometry.elbow + geometry.world(ends[snapshot.activeArm] ?? neutral.wrist)
    }

    /// Where the wrist rested at calibration.
    private func homeCenter(_ geometry: Geometry, neutral: Neutral) -> TherapyPoint {
        geometry.elbow + geometry.world(neutral.wrist)
    }

    /// Wide enough to forgive jitter, but never so wide that the start and target circles merge.
    private func circleRadius(_ neutral: Neutral) -> Double {
        let base = max(0.05, neutral.upperArm * targetRadiusRatio)
        guard let end = ends[snapshot.activeArm] else { return base }
        let separation = (end - neutral.wrist).length
        return max(0.03, min(base, separation * 0.42))
    }

    private mutating func process(
        _ geometry: Geometry,
        frame: TrackingObservation,
        neutral: Neutral,
        delta: Double
    ) {
        let time = frame.timestamp
        updatePath(geometry.wrist, time: time, scale: geometry.upperArm)
        let radius = circleRadius(neutral)

        if snapshot.phase == .returning {
            let home = homeCenter(geometry, neutral: neutral)
            let limit = radius * (returnHoldStartedAt == nil ? 1 : exitRadiusScale)
            guard (geometry.wrist - home).length <= limit else {
                maintainOrResetReturn(at: time)
                return
            }
            returnOutsideSince = nil
            if returnHoldStartedAt == nil { returnHoldStartedAt = time }
            snapshot.instructionKey = "rotation.returnHold"
            guard returnProgress(at: time) >= 1 else { return }
            returnHoldStartedAt = nil
            advanceArm()
            return
        }

        let target = targetCenter(geometry, neutral: neutral)
        let limit = radius * (targetHoldStartedAt == nil ? 1 : exitRadiusScale)
        guard (geometry.wrist - target).length <= limit else {
            maintainOrResetTarget(at: time)
            return
        }
        targetOutsideSince = nil
        if targetHoldStartedAt == nil { targetHoldStartedAt = time }
        snapshot.phase = .holding
        snapshot.instructionKey = "balance.hold"
        guard targetProgress(at: time) >= 1 else { return }
        snapshot.metrics.completedTouches += 1
        targetHoldStartedAt = nil
        targetOutsideSince = nil
        kinematics = nil
        if snapshot.metrics.completedTouches >= snapshot.goal {
            snapshot.phase = .complete
            snapshot.instructionKey = "rotation.complete"
        } else {
            snapshot.phase = .returning
            snapshot.instructionKey = "rotation.return"
        }
    }

    /// Moves on to the next arm. An arm that has not been calibrated yet needs its own resting pose.
    private mutating func advanceArm() {
        snapshot.activeArm = snapshot.armSelection.arm(after: snapshot.activeArm)
        kinematics = nil
        if neutrals[snapshot.activeArm] == nil {
            capture = nil
            snapshot.phase = .calibrating
            snapshot.calibrationProgress = 0
            snapshot.instructionKey = "rotation.elbowAtSide"
        } else if targets[snapshot.activeArm] == nil {
            beginRangeCalibration()
        } else {
            snapshot.phase = .reaching
            snapshot.instructionKey = reachKey(for: snapshot.activeArm)
            snapshot.targetAngle = Int((targets[snapshot.activeArm] ?? 0).rounded())
        }
    }

    private func reachKey(for arm: CrossingArm) -> String {
        let prefix = direction == .outward ? "rotation" : "internalRotation"
        return prefix + (arm == .right ? ".rotateRight" : ".rotateLeft")
    }

    private mutating func maintainOrResetTarget(at time: Double) {
        guard targetHoldStartedAt != nil else {
            targetOutsideSince = nil
            snapshot.phase = .reaching
            snapshot.instructionKey = reachKey(for: snapshot.activeArm)
            return
        }
        if targetOutsideSince == nil { targetOutsideSince = time }
        guard time - (targetOutsideSince ?? time) > trackingGracePeriod else {
            snapshot.phase = .holding
            snapshot.instructionKey = "balance.hold"
            return
        }
        targetHoldStartedAt = nil
        targetOutsideSince = nil
        snapshot.phase = .reaching
        snapshot.instructionKey = reachKey(for: snapshot.activeArm)
    }

    private mutating func maintainOrResetReturn(at time: Double) {
        guard returnHoldStartedAt != nil else {
            returnOutsideSince = nil
            snapshot.instructionKey = "rotation.return"
            return
        }
        if returnOutsideSince == nil { returnOutsideSince = time }
        guard time - (returnOutsideSince ?? time) > trackingGracePeriod else {
            snapshot.instructionKey = "rotation.returnHold"
            return
        }
        returnHoldStartedAt = nil
        returnOutsideSince = nil
        snapshot.instructionKey = "rotation.return"
    }

    private func targetProgress(at time: Double) -> Double {
        guard let targetHoldStartedAt else { return 0 }
        return min(1, max(0, (time - targetHoldStartedAt) / targetHoldDuration))
    }

    private func returnProgress(at time: Double) -> Double {
        guard let returnHoldStartedAt else { return 0 }
        return min(1, max(0, (time - returnHoldStartedAt) / returnHoldDuration))
    }

    private mutating func clearTransientEvidence() {
        targetHoldStartedAt = nil
        targetOutsideSince = nil
        returnHoldStartedAt = nil
        returnOutsideSince = nil
        kinematics = nil
        compensationCandidateSince = nil
        compensationClearSince = nil
        confirmedCompensation = nil
        compensationLatched = false
        snapshot.compensation = TrunkCompensation()
    }

    // MARK: - Compensation

    private func rawCompensation(
        _ geometry: Geometry,
        torso: TorsoBaseline,
        neutral: Neutral
    ) -> TrunkCompensation {
        let spine = geometry.spineUnit
        let lean = atan2(
            torso.spineUnit.x * spine.y - torso.spineUnit.y * spine.x,
            torso.spineUnit.dotProduct(spine)
        ) * 180 / .pi
        let shift = abs(geometry.spine.dotProduct(torso.lateralUnit) - torso.neckLateralOffset)
            / torso.shoulderWidth
        let turn = max(0, 1 - geometry.normalizedShoulderWidth / torso.normalizedShoulderWidth)
        let elbowOut = (geometry.elbow - geometry.shoulder).dotProduct(geometry.outward)
        let elbowAway = (elbowOut - neutral.elbowOut) / neutral.upperArm

        var reasons: Set<TrunkCompensation.Reason> = []
        if abs(lean) > leanThresholdDegrees { reasons.insert(.lateralLean) }
        if shift > lateralShiftThreshold { reasons.insert(.lateralShift) }
        if turn > rotationThreshold { reasons.insert(.shoulderRotation) }
        if elbowAway > elbowAwayThreshold { reasons.insert(.elbowAway) }
        return TrunkCompensation(
            leanDegrees: lean,
            lateralShiftRatio: shift,
            shoulderRotationRatio: turn,
            index: max(
                abs(lean) / leanThresholdDegrees,
                shift / lateralShiftThreshold,
                turn / rotationThreshold,
                elbowAway / elbowAwayThreshold
            ),
            reasons: reasons
        )
    }

    /// Rejects brief landmark spikes so they cannot cancel a long hold.
    private mutating func stabilized(_ raw: TrunkCompensation, at time: Double) -> TrunkCompensation {
        if raw.isCompensating {
            compensationClearSince = nil
            if confirmedCompensation != nil {
                confirmedCompensation = raw
                return raw
            }
            if compensationCandidateSince == nil { compensationCandidateSince = time }
            guard time - (compensationCandidateSince ?? time) >= compensationEntryDuration else {
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
        guard let confirmed = confirmedCompensation else {
            compensationClearSince = nil
            return raw
        }
        if compensationClearSince == nil { compensationClearSince = time }
        guard time - (compensationClearSince ?? time) >= compensationExitDuration else {
            return confirmed
        }
        confirmedCompensation = nil
        compensationClearSince = nil
        return raw
    }

    // MARK: - Path smoothness

    private mutating func updatePath(_ position: TherapyPoint, time: Double, scale: Double) {
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
        kinematics = Kinematics(time: time, position: position, velocity: velocity, acceleration: acceleration)
    }

    private var smoothness: Double {
        guard jerkSampleCount > 0 else { return 1 }
        return 1 / (1 + sqrt(jerkSquareSum / Double(jerkSampleCount)) * 0.002)
    }

    // MARK: - Geometry and overlay

    private func geometry(from frame: TrackingObservation) -> Geometry? {
        guard frame.personCount == 1 else { return nil }
        let right = snapshot.activeArm == .right
        let shoulderJoint: BodyJoint = right ? .rightShoulder : .leftShoulder
        let otherJoint: BodyJoint = right ? .leftShoulder : .rightShoulder
        let elbowJoint: BodyJoint = right ? .rightElbow : .leftElbow
        let wristJoint: BodyJoint = right ? .rightWrist : .leftWrist
        func point(_ joint: BodyJoint) -> TherapyPoint? {
            frame.point(joint, minimumConfidence: minimumConfidence)
        }
        guard let neck = point(.neck) ?? point(.nose),
              let leftShoulder = point(.leftShoulder),
              let rightShoulder = point(.rightShoulder),
              let shoulder = point(shoulderJoint),
              let otherShoulder = point(otherJoint),
              let elbow = point(elbowJoint),
              let wrist = point(wristJoint)
        else {
            return nil
        }
        let width = (rightShoulder - leftShoulder).length
        guard width > 0.08 else { return nil }
        let hips = [point(.leftHip), point(.rightHip)].compactMap { $0 }
        let center = (leftShoulder + rightShoulder).scaled(0.5)
        let root = point(.root)
            ?? (hips.count == 2 ? (hips[0] + hips[1]).scaled(0.5) : nil)
            ?? TherapyPoint(x: center.x, y: center.y - width * 1.05)
        let geometry = Geometry(
            neck: neck, root: root, leftShoulder: leftShoulder, rightShoulder: rightShoulder,
            shoulder: shoulder, elbow: elbow, wrist: wrist, otherShoulder: otherShoulder
        )
        guard geometry.spine.length > 0.08, geometry.upperArm > 0.04 else { return nil }
        if let torso {
            let ratio = geometry.shoulderWidth / torso.shoulderWidth
            let axis = (rightShoulder - leftShoulder).scaled(1 / width)
            guard (0.35...2.5).contains(ratio),
                  geometry.spineUnit.dotProduct(torso.spineUnit) > 0.35,
                  axis.dotProduct(torso.shoulderUnit) > 0.2
            else { return nil }
        }
        return geometry
    }

    private mutating func publishOverlay(
        _ geometry: Geometry,
        frame: TrackingObservation,
        neutral: Neutral? = nil
    ) {
        var target: TherapyPoint?
        var isReturn = false
        var radius = 0.055
        if let neutral {
            radius = circleRadius(neutral)
            if snapshot.phase == .returning {
                target = homeCenter(geometry, neutral: neutral)
                isReturn = true
            } else if snapshot.phase != .complete {
                target = targetCenter(geometry, neutral: neutral)
            }
        }
        let progress = isReturn ? returnProgress(at: frame.timestamp) : targetProgress(at: frame.timestamp)
        snapshot.overlay = BalanceOverlay(
            aspect: frame.aspect,
            midlineBase: geometry.root,
            midlineTop: geometry.neck,
            leftShoulder: geometry.leftShoulder,
            rightShoulder: geometry.rightShoulder,
            leftHip: geometry.root - geometry.lateralUnit.scaled(geometry.shoulderWidth * 0.22),
            rightHip: geometry.root + geometry.lateralUnit.scaled(geometry.shoulderWidth * 0.22),
            wrist: geometry.wrist,
            target: target,
            isReturnTarget: isReturn,
            targetRadius: radius,
            crossedMidline: snapshot.phase == .holding,
            targetProgress: progress,
            holdSecondsRemaining: holdSecondsRemaining(at: frame.timestamp, visible: target != nil, isReturn: isReturn),
            compensationWarning: snapshot.compensation.isCompensating,
            armChain: [geometry.shoulder, geometry.elbow, geometry.wrist],
            showsMidline: false
        )
        lastOverlayTimestamp = frame.timestamp
    }

    private func holdSecondsRemaining(at time: Double, visible: Bool, isReturn: Bool) -> Int? {
        guard visible else { return nil }
        if isReturn {
            guard let returnHoldStartedAt else { return nil }
            return max(1, Int(ceil(max(0, returnHoldDuration - (time - returnHoldStartedAt)))))
        }
        guard let targetHoldStartedAt else { return nil }
        return max(1, Int(ceil(max(0, targetHoldDuration - (time - targetHoldStartedAt)))))
    }
}

private extension TherapyPoint {
    func dotProduct(_ other: TherapyPoint) -> Double { x * other.x + y * other.y }
}
