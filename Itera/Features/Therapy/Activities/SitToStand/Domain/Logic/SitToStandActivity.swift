//
//  SitToStandActivity.swift
//  Itera
//
//  Created by Fauzan Azima on 03/11/2026.
//

import Foundation

/// Sit-to-stand with a forward trunk lean, measured from body joints seen from the side.
///
/// Forward lean and standing are sagittal-plane movements: from the front they only foreshorten
/// the body, so the session asks the patient to sit sideways to the camera. The tracked chain is
/// shoulder, hip, knee, and ankle on the side facing the camera. Three joint metrics follow the
/// patient from sitting to standing, with no target circles:
///
/// - **Knee angle** at hip–knee–ankle, about 90° seated and close to 180° standing.
/// - **Hip height** above the ankle, relative to leg length, which rises as the patient stands.
/// - **Trunk lean**, the angle of the hip-to-shoulder line from vertical, positive forward.
///
/// Nothing asks for a precise pose. Calibration holds a comfortable seated pose, then watches the
/// patient perform one sit-to-stand in their own way and records how far they lean and rise.
/// Practice follows the live metrics against fractions of that personal range. A repetition counts
/// only if some forward lean came before rising and the descent was not abrupt.
struct SitToStandActivity {
    private let goal: Int
    private var snapshot = SitToStandSnapshot()
    private var hold = StableHold()
    private var landmarkSmoother = MovementLandmarkSmoother()
    private var seated: Pose?
    private var standing: Pose?
    /// How far, in degrees, the patient leaned forward of their seated pose during the trial.
    private var leanGain = 0.0
    private var trial = Trial()
    private var suspended = false
    /// The leg followed so far. It changes only when the other leg is clearly better seen.
    private var followsLeftLeg = true
    private var forward = 1.0
    private var last: Double?
    private var lastValid: Double?
    private var sustainedSince: Double?
    private var countdown: Double?
    /// The patient must be back in the seat before the next repetition, or before practice starts.
    private var awaitingSeat = false
    private var returningBeforePractice = false
    private var repValid = true
    private var riseStartedAt = 0.0
    private var lowerStartedAt = 0.0
    private var cueExpiresAt = 0.0

    /// What the patient's own trial repetition has shown so far.
    private struct Trial {
        var maxKneeGain = 0.0
        var maxHeightGain = 0.0
        var peakLean = 0.0
        var bestPose: Pose?
        var reachedStand = false
        /// The patient has held their standing pose for the full countdown.
        var standHeld = false
    }

    private struct Pose {
        let joints: SitToStandJoints
        let knee: Double
        let leg: Double
        let height: Double
        let lean: Double
    }

    private enum Limits {
        static let confidence: Float = 0.3
        static let minimumLeg = 0.15
        static let minimumTrunk = 0.06
        static let seatedHold = 3.0
        /// How long the patient holds the standing pose during the trial.
        static let standingHold = 3.0
        /// A pose this close to the best so far counts as the standing pose.
        static let standingPeakFraction = 0.85
        /// Only rules out a patient who is already standing; any comfortable seat is accepted.
        static let seatedKnee = 45.0...145.0
        static let maximumSeatedLean = 45.0
        /// The smallest rise that separates a real stand from landmark noise during the trial.
        static let minimumKneeGain = 25.0
        static let minimumHeightGain = 0.15
        static let trialSeatedFraction = 0.25
        static let trialSettle = 0.5
        /// Lean needed before rising, never less than a visible tilt and otherwise a share of
        /// the patient's own trial lean.
        static let minimumLeanTarget = 5.0
        static let leanTargetFraction = 0.5
        static let minimumLeanFloor = 3.0
        static let leanLostFraction = 0.25
        static let seatedRise = 0.2
        static let liftRise = 0.3
        static let standingRise = 0.75
        static let loweringRise = 0.7
        static let dwell = 0.25
        static let minimumDescent = 0.5
        static let cueDuration = 3.0
    }

    init(goal: Int) { self.goal = goal }

    /// What the patient is doing and how far along they are, as the screens present it.
    var presentation: SitToStandSnapshot {
        var value = snapshot

        if countdown != nil {
            value.phase = .countdown
        } else if standing != nil {
            value.phase = returningBeforePractice ? .returnToSeat : .practice
        } else {
            value.phase = seated == nil ? .seatedCapture : .trial
        }

        return value
    }

    /// Whether the goal number of repetitions has been reached.
    var isFinished: Bool { snapshot.count >= goal }

    /// Stops following the patient, for example while the session is paused.
    mutating func suspend() {
        suspended = true
        landmarkSmoother.reset()
        interrupt()
    }

    mutating func resume() {
        suspended = false

        if countdown != nil {
            countdown = nil
            returningBeforePractice = true
            awaitingSeat = true
        }
    }

    /// Forgets the calibrated poses so the patient starts again from the seated hold.
    mutating func recalibrate() {
        seated = nil
        standing = nil
        trial = Trial()
        countdown = nil
        returningBeforePractice = false
        snapshot.instruction = "sts.holdSeated"
        interrupt()
    }

    /// Time moves on even when no usable frame arrives, so a lost patient is noticed.
    mutating func tick(_ time: Double) {
        if let last, time - last > 0.15 {
            hold.clear()
            sustainedSince = nil
            snapshot.progress = 0
        }

        if let lastValid, time - lastValid > 0.5 {
            snapshot.joints = nil
            snapshot.trackingMessage = "sts.trackingLost"
            resetRepetition()
            awaitingSeat = standing != nil
        }
    }

    mutating func observe(_ frame: TrackingObservation) {
        guard !suspended else {
            return
        }

        consume(landmarkSmoother.consume(frame))
    }

    private mutating func interrupt() {
        hold.clear()
        sustainedSince = nil
        last = nil
        lastValid = nil
        snapshot.joints = nil
        snapshot.progress = 0
        snapshot.trackingMessage = nil
        resetRepetition()
        awaitingSeat = standing != nil
    }

    private mutating func resetRepetition() {
        snapshot.stage = .seated
        snapshot.leanReached = false
        repValid = true
        sustainedSince = nil
    }

    // MARK: - Joint metrics

    /// One side's joint chain with its mean landmark confidence, or nil if any joint is missing.
    private func chain(in frame: TrackingObservation, left: Bool) -> (joints: SitToStandJoints, score: Float)? {
        let names: [BodyJoint] = left
            ? [.leftShoulder, .leftHip, .leftKnee, .leftAnkle]
            : [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
        let points = names.compactMap { frame.point($0, minimumConfidence: Limits.confidence) }
        guard points.count == names.count else {
            return nil
        }
        let score = names.reduce(Float(0)) { $0 + (frame.joints[$1]?.confidence ?? 0) } / Float(names.count)
        return (
            SitToStandJoints(shoulder: points[0], hip: points[1], knee: points[2], ankle: points[3]),
            score
        )
    }

    /// The patient may face either way, so follow the leg the camera sees best. The current leg
    /// is kept unless the other is clearly better, which stops the chain flickering between sides.
    private mutating func bestChain(in frame: TrackingObservation) -> SitToStandJoints? {
        let left = chain(in: frame, left: true)
        let right = chain(in: frame, left: false)
        switch (left, right) {
        case (nil, nil):
            return nil
        case (let only?, nil):
            followsLeftLeg = true
            return only.joints
        case (nil, let only?):
            followsLeftLeg = false
            return only.joints
        case (let left?, let right?):
            let current = followsLeftLeg ? left : right
            let other = followsLeftLeg ? right : left
            if other.score > current.score + 0.15 {
                followsLeftLeg.toggle()
                return other.joints
            }
            return current.joints
        }
    }

    private func angle(at vertex: TherapyPoint, _ a: TherapyPoint, _ b: TherapyPoint) -> Double? {
        let u = a - vertex
        let v = b - vertex
        let length = u.length * v.length
        guard length > 0.0001 else {
            return nil
        }
        let cosine = (u.x * v.x + u.y * v.y) / length
        return acos(max(-1, min(1, cosine))) * 180 / .pi
    }

    private mutating func pose(in frame: TrackingObservation) -> Pose? {
        guard let joints = bestChain(in: frame),
              let knee = angle(at: joints.knee, joints.hip, joints.ankle)
        else {
            return nil
        }
        let leg = (joints.hip - joints.knee).length + (joints.knee - joints.ankle).length
        let trunk = joints.shoulder - joints.hip
        let height = (joints.hip.y - joints.ankle.y) / max(leg, 0.0001)
        guard leg > Limits.minimumLeg, trunk.length > Limits.minimumTrunk, height > 0 else {
            return nil
        }
        // Knees point the way the patient faces while seated, so latch that direction until the
        // seated pose is captured; standing makes the thigh too vertical to tell.
        let reach = joints.knee.x - joints.hip.x
        if seated == nil, abs(reach) > 0.02 {
            forward = reach > 0 ? 1 : -1
        }
        let lean = atan2(forward * trunk.x, trunk.y) * 180 / .pi
        return Pose(joints: joints, knee: knee, leg: leg, height: height, lean: lean)
    }

    /// Progress from the calibrated seated pose (0) to the calibrated standing pose (1), averaging
    /// knee extension and hip rise so one noisy joint cannot decide it alone.
    private func rise(of pose: Pose, seated: Pose, standing: Pose) -> Double {
        let kneeSpan = max(1, standing.knee - seated.knee)
        let heightSpan = max(0.01, standing.height - seated.height)
        let knee = (pose.knee - seated.knee) / kneeSpan
        let height = (pose.height - seated.height) / heightSpan
        return min(1, max(0, (knee + height) / 2))
    }

    // MARK: - Observation

    private mutating func consume(_ frame: TrackingObservation) {
        let time = frame.timestamp
        guard time.isFinite, last.map({ time > $0 }) ?? true else {
            interrupt()
            return
        }
        let gap = last.map { time - $0 } ?? 0
        if gap > 0.15 {
            hold.clear()
            sustainedSince = nil
        }
        if gap > 0.5 {
            resetRepetition()
            awaitingSeat = standing != nil
        }
        last = time
        if time > cueExpiresAt {
            snapshot.cue = nil
        }
        guard let current = pose(in: frame) else {
            hold.clear()
            sustainedSince = nil
            snapshot.progress = 0
            snapshot.joints = nil
            snapshot.trackingMessage = "sts.trackingLost"
            return
        }
        snapshot.trackingMessage = nil
        if lastValid.map({ time - $0 > 0.5 }) == true {
            resetRepetition()
            awaitingSeat = standing != nil
        }
        lastValid = time
        snapshot.aspect = frame.aspect
        snapshot.joints = current.joints
        snapshot.kneeAngle = current.knee
        snapshot.trunkLean = current.lean
        guard let seated else {
            captureSeated(current, time: time)
            return
        }
        guard let standing else {
            observeTrial(current, seated: seated, time: time)
            return
        }
        practice(current, seated: seated, standing: standing, time: time)
    }

    // MARK: - Calibration

    private mutating func captureSeated(_ current: Pose, time: Double) {
        let seatedHere = Limits.seatedKnee.contains(current.knee)
            && current.lean <= Limits.maximumSeatedLean
        guard seatedHere else {
            hold.clear()
            publish(hold: Limits.seatedHold, instruction: "sts.sitDown")
            return
        }
        hold.consume(
            current.joints.hip, time: time, duration: Limits.seatedHold,
            tolerance: current.leg * 0.12
        )
        publish(hold: Limits.seatedHold, instruction: "sts.holdSeated")
        guard hold.progress >= 1 else {
            return
        }
        seated = current
        trial = Trial()
        snapshot.instruction = "sts.trial"
        hold.clear()
        snapshot.progress = 0
    }

    /// Watches one sit-to-stand done in the patient's own way and keeps how far they leaned and
    /// rose. It finishes once they have stood and settled back into the seat.
    private mutating func observeTrial(_ current: Pose, seated: Pose, time: Double) {
        snapshot.progress = 0
        let kneeGain = current.knee - seated.knee
        let heightGain = current.height - seated.height
        if !trial.reachedStand, heightGain < 0.1 {
            trial.peakLean = max(trial.peakLean, current.lean)
        }
        if kneeGain > trial.maxKneeGain || heightGain > trial.maxHeightGain {
            let better = kneeGain / max(1, trial.maxKneeGain) + heightGain / max(0.01, trial.maxHeightGain)
            let previous = trial.bestPose.map {
                ($0.knee - seated.knee) / max(1, trial.maxKneeGain)
                    + ($0.height - seated.height) / max(0.01, trial.maxHeightGain)
            } ?? 0
            if trial.bestPose == nil || better >= previous {
                trial.bestPose = current
            }
        }
        trial.maxKneeGain = max(trial.maxKneeGain, kneeGain)
        trial.maxHeightGain = max(trial.maxHeightGain, heightGain)
        if trial.maxKneeGain >= Limits.minimumKneeGain, trial.maxHeightGain >= Limits.minimumHeightGain {
            trial.reachedStand = true
        }
        guard trial.reachedStand else {
            snapshot.instruction = "sts.trial"
            hold.clear()
            sustainedSince = nil
            return
        }
        holdStandingPose(current, kneeGain: kneeGain, heightGain: heightGain, time: time)
        let settledKnee = kneeGain <= max(10, trial.maxKneeGain * Limits.trialSeatedFraction)
        let settledHeight = heightGain <= trial.maxHeightGain * Limits.trialSeatedFraction
        guard sustainedFor(settledKnee && settledHeight, at: time, seconds: Limits.trialSettle),
              let best = trial.bestPose
        else {
            return
        }
        standing = best
        leanGain = max(0, trial.peakLean - seated.lean)
        returningBeforePractice = true
        awaitingSeat = true
        sustainedSince = nil
        snapshot.instruction = "sts.sitDown"
    }

    /// Counts down while the patient stays still at the top of their stand, so the standing pose
    /// is as deliberate as the seated one. It is guidance: sitting early still finishes the trial.
    private mutating func holdStandingPose(_ current: Pose, kneeGain: Double, heightGain: Double, time: Double) {
        guard !trial.standHeld else {
            snapshot.instruction = "sts.sitDown"
            return
        }

        let nearPeak = kneeGain >= trial.maxKneeGain * Limits.standingPeakFraction
            && heightGain >= trial.maxHeightGain * Limits.standingPeakFraction

        guard nearPeak else {
            hold.clear()
            snapshot.instruction = "sts.trial"
            return
        }

        hold.consume(
            current.joints.hip, time: time, duration: Limits.standingHold,
            tolerance: current.leg * 0.12
        )
        publish(hold: Limits.standingHold, instruction: "sts.holdStanding")

        guard hold.progress >= 1 else {
            return
        }

        trial.standHeld = true
        hold.clear()
        snapshot.progress = 0
        snapshot.instruction = "sts.sitDown"
    }

    private mutating func publish(hold duration: Double, instruction: String) {
        snapshot.progress = hold.progress
        snapshot.instruction = instruction
        snapshot.seconds = Int(ceil(duration * (1 - hold.progress)))
    }

    // MARK: - Practice

    /// True once `condition` has held continuously for the dwell time.
    private mutating func sustained(_ condition: Bool, at time: Double) -> Bool {
        sustainedFor(condition, at: time, seconds: Limits.dwell)
    }

    private mutating func sustainedFor(_ condition: Bool, at time: Double, seconds: Double) -> Bool {
        guard condition else {
            sustainedSince = nil
            return false
        }
        if sustainedSince == nil {
            sustainedSince = time
        }
        return time - (sustainedSince ?? time) >= seconds
    }

    private mutating func flag(_ cue: String, at time: Double) {
        repValid = false
        snapshot.cue = cue
        cueExpiresAt = time + Limits.cueDuration
    }

    private mutating func practice(_ current: Pose, seated: Pose, standing: Pose, time: Double) {
        if let deadline = countdown {
            snapshot.instruction = "session.countdown"
            snapshot.seconds = max(0, Int(ceil(deadline - time)))
            snapshot.progress = max(0, min(1, (deadline - time) / 3))
            guard time >= deadline else {
                return
            }
            countdown = nil
            snapshot.progress = 0
        }
        let rise = rise(of: current, seated: seated, standing: standing)
        snapshot.rise = rise
        if awaitingSeat {
            snapshot.instruction = "sts.sitDown"
            guard sustained(rise <= Limits.seatedRise, at: time) else {
                return
            }
            awaitingSeat = false
            resetRepetition()
            if returningBeforePractice {
                returningBeforePractice = false
                countdown = time + 3
                snapshot.seconds = 3
                snapshot.progress = 1
            }
            return
        }
        let leanTarget = seated.lean + max(Limits.minimumLeanTarget, leanGain * Limits.leanTargetFraction)
        let leanFloor = seated.lean + max(Limits.minimumLeanFloor, leanGain * Limits.leanLostFraction)
        switch snapshot.stage {
        case .seated:
            snapshot.instruction = "sts.leanForward"
            if rise > Limits.liftRise {
                // Standing without the controlled lean: the repetition is lost, not the session.
                flag("sts.leanFirst", at: time)
                snapshot.stage = .rising
                riseStartedAt = time
            } else if sustained(current.lean >= leanTarget && rise <= Limits.liftRise, at: time) {
                snapshot.leanReached = true
                snapshot.stage = .leaning
                sustainedSince = nil
            }
        case .leaning:
            snapshot.instruction = "sts.standUp"
            if rise > Limits.liftRise {
                if current.lean < leanFloor {
                    flag("sts.leanFirst", at: time)
                }
                snapshot.stage = .rising
                riseStartedAt = time
            } else if current.lean < leanFloor {
                resetRepetition()
            }
        case .rising:
            snapshot.instruction = "sts.standUp"
            if sustained(rise >= Limits.standingRise, at: time) {
                snapshot.stage = .standing
                sustainedSince = nil
            } else if rise <= Limits.seatedRise, time - riseStartedAt > 0.3 {
                // Sat back down without standing: start the repetition again.
                resetRepetition()
            }
        case .standing:
            snapshot.instruction = "sts.sitDown"
            if rise < Limits.loweringRise {
                snapshot.stage = .lowering
                lowerStartedAt = time
                sustainedSince = nil
            }
        case .lowering:
            snapshot.instruction = "sts.sitDown"
            if rise >= Limits.standingRise {
                snapshot.stage = .standing
                sustainedSince = nil
            } else if sustained(rise <= Limits.seatedRise, at: time) {
                if time - lowerStartedAt < Limits.minimumDescent, repValid {
                    flag("sts.slowDown", at: time)
                }
                if repValid {
                    snapshot.count += 1
                }
                resetRepetition()
            }
        }
    }
}
