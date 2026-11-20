//
//  SitToStandActivity.swift
//  Tuntun
//
//  Created by Fauzan Azima on 03/11/2026.
//

import Foundation

/// Sit-to-stand, measured from body joints seen from the side.
///
/// Forward lean and standing are sagittal-plane movements: from the front they only foreshorten
/// the body, so the session asks the patient to sit sideways to the camera. The camera frames the
/// seated patient down to the knees, so the tracked chain is shoulder, hip, and knee on the side
/// facing the camera; the ankle is never needed. Three joint metrics follow the patient from
/// sitting to standing, with no target circles:
///
/// - **Thigh elevation**, the knee-to-hip line above horizontal: near 0° seated, close to 90°
///   standing. With the feet flat it follows knee extension, and it ignores trunk lean.
/// - **Hip rise**, the hip's height in the frame relative to trunk length, compared with the
///   seated pose. The camera stays still during a session; Recalibrate covers a moved camera.
/// - **Trunk lean**, the angle of the hip-to-shoulder line from vertical, positive forward.
///
/// Nothing asks for a precise pose. Calibration holds a comfortable seat, then a comfortable
/// stand, then waits for the patient to sit back down; those two held poses are their personal
/// range. Practice follows the live rise against fractions of it: reaching the stand and sitting
/// back down are the two halves of a repetition, and it counts if the descent was not abrupt.
struct SitToStandActivity {
    private let goal: Int
    private var snapshot = SitToStandSnapshot()
    private var hold = StableHold()
    private var landmarkSmoother = MovementLandmarkSmoother(minimumConfidence: 0.3)
    private var seated: Pose?
    private var standing: Pose?
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
        var maxThighGain = 0.0
        var maxHeightGain = 0.0
        var bestPose: Pose?
        var reachedStand = false
        /// The patient has held their standing pose for the full countdown.
        var standHeld = false
    }

    private struct Pose {
        let joints: SitToStandJoints
        /// Thigh elevation above horizontal, in degrees.
        let thigh: Double
        /// Shoulder–hip–knee angle, recorded for clinicians but never used for counting.
        let hipAngle: Double
        /// Thigh-plus-trunk length that scales hold tolerances.
        let scale: Double
        /// Hip height in the frame in trunk lengths; only differences from the seated pose matter.
        let height: Double
        let lean: Double
    }

    private enum Limits {
        static let confidence: Float = 0.3
        static let minimumThigh = 0.06
        static let minimumTrunk = 0.06
        static let seatedHold = 3.0
        /// How long the patient holds the standing pose during the trial.
        static let standingHold = 3.0
        /// A pose this close to the best so far counts as the standing pose.
        static let standingPeakFraction = 0.85
        /// Only rules out a patient who is already standing; any comfortable seat is accepted.
        static let seatedThigh = -30.0...40.0
        static let maximumSeatedLean = 45.0
        /// The smallest rise that separates a real stand from landmark noise during the trial.
        static let minimumThighGain = 25.0
        static let minimumHeightGain = 0.15
        static let trialSeatedFraction = 0.25
        static let trialSettle = 0.5
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

    /// Starts another set with the same calibrated poses: the count restarts and the patient
    /// sits back down for the three-second countdown, as before the first practice repetition.
    mutating func startNextSet() {
        snapshot.count = 0
        countdown = nil
        returningBeforePractice = true
        awaitingSeat = true
        interrupt()
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
            snapshot.guide = nil
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
        snapshot.guide = nil
        snapshot.progress = 0
        snapshot.trackingMessage = nil
        resetRepetition()
        awaitingSeat = standing != nil
    }

    private mutating func resetRepetition() {
        snapshot.stage = .seated
        snapshot.repetitionProgress = 0
        snapshot.repetitionCounts = true
        repValid = true
        sustainedSince = nil
    }

    // MARK: - Joint metrics

    /// One side's joint chain with its mean landmark confidence, or nil if any joint is missing.
    private func chain(in frame: TrackingObservation, left: Bool) -> (joints: SitToStandJoints, score: Float)? {
        let names: [BodyJoint] = left
            ? [.leftShoulder, .leftHip, .leftKnee]
            : [.rightShoulder, .rightHip, .rightKnee]
        let points = names.compactMap { frame.point($0, minimumConfidence: Limits.confidence) }
        guard points.count == names.count else {
            return nil
        }
        let score = names.reduce(Float(0)) { $0 + (frame.joints[$1]?.confidence ?? 0) } / Float(names.count)
        return (
            SitToStandJoints(shoulder: points[0], hip: points[1], knee: points[2]),
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
        JointAngle.degrees(at: vertex, a, b)
    }

    private mutating func pose(in frame: TrackingObservation) -> Pose? {
        guard let joints = bestChain(in: frame),
              let hipAngle = angle(at: joints.hip, joints.shoulder, joints.knee)
        else {
            return nil
        }
        let thighVector = joints.hip - joints.knee
        let trunk = joints.shoulder - joints.hip
        guard thighVector.length > Limits.minimumThigh, trunk.length > Limits.minimumTrunk else {
            return nil
        }
        let thigh = atan2(thighVector.y, abs(thighVector.x)) * 180 / .pi
        let height = joints.hip.y / trunk.length
        // Knees point the way the patient faces while seated, so latch that direction until the
        // seated pose is captured; standing makes the thigh too vertical to tell.
        let reach = joints.knee.x - joints.hip.x
        if seated == nil, abs(reach) > 0.02 {
            forward = reach > 0 ? 1 : -1
        }
        let lean = atan2(forward * trunk.x, trunk.y) * 180 / .pi
        return Pose(
            joints: joints,
            thigh: thigh,
            hipAngle: hipAngle,
            scale: thighVector.length + trunk.length,
            height: height,
            lean: lean
        )
    }

    /// Progress from the calibrated seated pose (0) to the calibrated standing pose (1), averaging
    /// thigh elevation and hip rise so one noisy joint cannot decide it alone.
    private func rise(of pose: Pose, seated: Pose, standing: Pose) -> Double {
        let thighSpan = max(1, standing.thigh - seated.thigh)
        let heightSpan = max(0.01, standing.height - seated.height)
        let thigh = (pose.thigh - seated.thigh) / thighSpan
        let height = (pose.height - seated.height) / heightSpan
        return min(1, max(0, (thigh + height) / 2))
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
            snapshot.guide = nil
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
        snapshot.hipAngle = current.hipAngle
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

    /// The starting position: a comfortable seat held still. Completing it pops the hip circle.
    private mutating func captureSeated(_ current: Pose, time: Double) {
        snapshot.guide = nil

        let seatedHere = Limits.seatedThigh.contains(current.thigh)
            && current.lean <= Limits.maximumSeatedLean

        guard seatedHere else {
            hold.clear()
            publish(hold: Limits.seatedHold, instruction: "sts.sitDown")
            return
        }

        hold.consume(
            current.joints.hip,
            time: time,
            duration: Limits.seatedHold,
            tolerance: current.scale * 0.12
        )
        publish(hold: Limits.seatedHold, instruction: "sts.holdSeated")

        guard hold.progress >= 1 else {
            return
        }

        seated = current
        trial = Trial()
        snapshot.completions += 1
        snapshot.instruction = "sts.holdStanding"
        hold.clear()
        snapshot.progress = 0
    }

    /// The standing position: the patient stands up under the up arrow and holds their stand,
    /// which pops the hip circle, then sits back down under the down arrow. Calibration finishes
    /// only once the stand was held and the patient has settled back into the seat.
    private mutating func observeTrial(_ current: Pose, seated: Pose, time: Double) {
        snapshot.progress = 0

        let thighGain = current.thigh - seated.thigh
        let heightGain = current.height - seated.height

        recordTrialPeak(current, seated: seated, thighGain: thighGain, heightGain: heightGain)

        guard trial.reachedStand else {
            snapshot.instruction = "sts.holdStanding"
            snapshot.guide = standUpGuide(current, seated: seated, standing: nil)
            hold.clear()
            sustainedSince = nil
            return
        }

        holdStandingPose(current, thighGain: thighGain, heightGain: heightGain, time: time)
        snapshot.guide = trialGuide(current, seated: seated)

        guard trial.standHeld else {
            sustainedSince = nil
            return
        }

        let settledThigh = thighGain <= max(10, trial.maxThighGain * Limits.trialSeatedFraction)
        let settledHeight = heightGain <= trial.maxHeightGain * Limits.trialSeatedFraction

        guard sustainedFor(settledThigh && settledHeight, at: time, seconds: Limits.trialSettle),
              let best = trial.bestPose
        else {
            return
        }

        standing = best
        returningBeforePractice = true
        awaitingSeat = true
        sustainedSince = nil
        snapshot.instruction = "sts.sitDown"
    }

    /// Keeps the highest stand seen so far, weighing thigh elevation and hip rise together.
    private mutating func recordTrialPeak(
        _ current: Pose,
        seated: Pose,
        thighGain: Double,
        heightGain: Double
    ) {
        if thighGain > trial.maxThighGain || heightGain > trial.maxHeightGain {
            let better = thighGain / max(1, trial.maxThighGain)
                + heightGain / max(0.01, trial.maxHeightGain)
            let previous = trial.bestPose.map {
                ($0.thigh - seated.thigh) / max(1, trial.maxThighGain)
                    + ($0.height - seated.height) / max(0.01, trial.maxHeightGain)
            } ?? 0

            if trial.bestPose == nil || better >= previous {
                trial.bestPose = current
            }
        }

        trial.maxThighGain = max(trial.maxThighGain, thighGain)
        trial.maxHeightGain = max(trial.maxHeightGain, heightGain)

        if trial.maxThighGain >= Limits.minimumThighGain,
           trial.maxHeightGain >= Limits.minimumHeightGain {
            trial.reachedStand = true
        }
    }

    /// Counts down while the patient stays still at the top of their stand, so the standing pose
    /// is as deliberate as the seated one. Sitting before it completes asks them to stand again.
    private mutating func holdStandingPose(_ current: Pose, thighGain: Double, heightGain: Double, time: Double) {
        guard !trial.standHeld else {
            snapshot.instruction = "sts.sitDown"
            return
        }

        let nearPeak = thighGain >= trial.maxThighGain * Limits.standingPeakFraction
            && heightGain >= trial.maxHeightGain * Limits.standingPeakFraction

        guard nearPeak else {
            hold.clear()
            snapshot.instruction = "sts.holdStanding"
            return
        }

        hold.consume(
            current.joints.hip,
            time: time,
            duration: Limits.standingHold,
            tolerance: current.scale * 0.12
        )
        publish(hold: Limits.standingHold, instruction: "sts.holdStanding")

        guard hold.progress >= 1 else {
            return
        }

        trial.standHeld = true
        snapshot.completions += 1
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

    /// One repetition is a stand and a controlled sit. Reaching the stand pops the hip circle;
    /// sitting back down counts the repetition and pops it again.
    private mutating func practice(_ current: Pose, seated: Pose, standing: Pose, time: Double) {
        if let deadline = countdown {
            snapshot.instruction = "session.countdown"
            snapshot.guide = nil
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
            snapshot.repetitionProgress = 0
            snapshot.repetitionCounts = false
            snapshot.guide = sitDownGuide(current, seated: seated, from: standing)

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

        switch snapshot.stage {
        case .seated:
            snapshot.instruction = "sts.standUp"

            if rise > Limits.liftRise {
                snapshot.stage = .rising
                riseStartedAt = time
            }
        case .rising:
            snapshot.instruction = "sts.standUp"

            if sustained(rise >= Limits.standingRise, at: time) {
                // The pop and the next instruction land on the same frame, so the pop sound
                // leads straight into "sit down".
                snapshot.stage = .standing
                snapshot.instruction = "sts.sitDown"
                snapshot.completions += 1
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
                    snapshot.completions += 1
                }

                resetRepetition()
            }
        }

        publishRepetition(current, seated: seated, standing: standing, rise: rise)
    }

    // MARK: - Repetition guidance

    /// Sets the arc and the arrow for the current half of the repetition: up to the stand, then
    /// down to the seat. Each half fills the arc from empty, and its completion pops the circle.
    private mutating func publishRepetition(
        _ current: Pose,
        seated: Pose,
        standing: Pose,
        rise: Double
    ) {
        guard repValid else {
            snapshot.repetitionProgress = 0
            snapshot.repetitionCounts = false
            snapshot.guide = nil
            return
        }

        snapshot.repetitionCounts = true

        switch snapshot.stage {
        case .seated, .rising:
            snapshot.repetitionProgress = clamped(rise / Limits.standingRise)
            snapshot.guide = standUpGuide(current, seated: seated, standing: standing)
        case .standing:
            snapshot.repetitionProgress = 0
            snapshot.guide = sitDownGuide(current, seated: seated, from: standing)
        case .lowering:
            let descent = (Limits.standingRise - rise) / (Limits.standingRise - Limits.seatedRise)
            snapshot.repetitionProgress = clamped(descent)
            snapshot.guide = sitDownGuide(current, seated: seated, from: standing)
        }
    }

    /// The trial after the patient has stood: no arrow while the stand is held, up toward the best
    /// stand while they are below it, and down to the seat once it is held.
    private func trialGuide(_ current: Pose, seated: Pose) -> SitToStandGuide? {
        guard let best = trial.bestPose else {
            return nil
        }

        if trial.standHeld {
            return sitDownGuide(current, seated: seated, from: best)
        }

        if snapshot.progress > 0 {
            return nil
        }

        return standUpGuide(current, seated: seated, standing: best)
    }

    /// From the seated hip up to the standing hip. Before the trial has shown a stand, it points
    /// one trunk length straight up.
    private func standUpGuide(_ current: Pose, seated: Pose, standing: Pose?) -> SitToStandGuide {
        let hip = seated.joints.hip
        let trunk = (seated.joints.shoulder - hip).length
        let tip = standing?.joints.hip ?? hip + TherapyPoint(x: 0, y: trunk)

        return SitToStandGuide(
            tail: hip,
            tip: tip,
            joint: current.joints.hip
        )
    }

    private func sitDownGuide(_ current: Pose, seated: Pose, from standing: Pose) -> SitToStandGuide {
        SitToStandGuide(
            tail: standing.joints.hip,
            tip: seated.joints.hip,
            joint: current.joints.hip
        )
    }

    private func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
