//
//  SitToStandActivity.swift
//  Tuntun
//
//  Created by Fauzan Azima on 03/11/2026.
//

import Foundation

/// Sit-to-stand, measured from body joints seen from the side.
///
/// A shoulder and hip on the same side are the minimum evidence. Knees are optional, so a
/// close camera can frame the torso. Both hip and shoulder must rise from the held seated
/// baseline; trunk length and uprightness corroborate the held standing endpoint. This is a
/// calibrated image-space movement aid, not proof of knee extension or a clinical assessment.
/// The camera must stay still and the shoulder and hip must remain in frame throughout.
///
/// Nothing asks for a precise pose. Calibration holds a comfortable seat, then a comfortable
/// stand, then waits for the patient to sit back down; those two held poses are their personal
/// range. Practice follows the live rise against fractions of it: reaching the stand and sitting
/// back down are the two halves of a repetition, and it counts if the descent was not abrupt.
struct SitToStandActivity {
    private let goal: Int
    private var snapshot = SitToStandSnapshot()
    private var hold = StableHold()
    private var landmarkSmoother = MovementLandmarkSmoother(minimumConfidence: 0.2)
    private var seated: Pose?
    private var standing: Pose?
    private var trial = Trial()
    private var suspended = false
    /// The torso side followed so far; changes only when the other side is clearly better seen,
    /// and never once the seat is captured, because the calibrated poses belong to that side.
    private var followsLeftLeg = true
    /// A frame without usable torso evidence arrived since the last pose. The next hold sample
    /// then earns nothing for the interval that spans it, so unobserved time is never credited.
    private var evidenceGap = false
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
        var maxHeightGain = 0.0
        var bestPose: Pose?
        /// Mean hip over the held stand: the standing reference, steadier than the single
        /// highest frame, which a confirmed detector jump could push out of reach.
        var heldHip: TherapyPoint?
        var reachedStand = false
        /// The patient has held their standing pose for the full countdown.
        var standHeld = false
        /// When the hip last rose clearly above the previous peak: the patient is still rising.
        var peakRaisedAt = 0.0
    }

    private struct Pose {
        let joints: SitToStandJoints
        /// Thigh elevation above horizontal, in degrees, from a clearly seen knee only.
        let thigh: Double?
        /// Shoulder–hip–knee angle, recorded for clinicians but never used for counting.
        let hipAngle: Double
        /// Trunk length that scales hold tolerances.
        let scale: Double
        let lean: Double
    }

    private enum Limits {
        static let confidence: Float = 0.3
        /// A knee near the cropped lower edge can be weaker than the torso. It still needs an
        /// actual current-frame landmark; missing knees are omitted, never inferred.
        static let kneeConfidence: Float = 0.2
        /// Only a clearly seen knee may veto the seat as "already standing"; a weak knee at the
        /// cropped lower edge wanders and kept restarting the seated hold.
        static let reliableKneeConfidence: Float = 0.3
        /// How long a hold survives frames without torso evidence. That time earns nothing.
        static let holdGrace = 0.4
        /// The longest step between consecutive fresh samples that earns hold time.
        static let holdStep = 0.15
        /// How long the last pose stays drawn, without a tracking-lost message, while the torso
        /// is briefly missing. Nothing advances on it.
        static let lostGrace = 0.5
        static let holdTolerance = 0.12
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
        static let minimumHeightGain = 0.25
        static let standingTrunkScale = 0.7...1.35
        static let maximumStandingLean = 40.0
        static let trialSeatedFraction = 0.25
        static let trialSettle = 0.5
        static let seatedRise = 0.2
        static let liftRise = 0.3
        static let standingRise = 0.75
        static let loweringRise = 0.7
        static let dwell = 0.25
        /// A rise above the peak by more than this (in seated trunk lengths) means the patient is
        /// still rising rather than jittering at the top.
        static let peakMargin = 0.03
        /// How long the hip must stop setting new peaks before the standing hold may start, so its
        /// arc begins once the patient has arrived instead of restarting during the rise.
        static let arrivalSettle = 0.3
        /// A hold sample may stray beyond the tolerance this long without restarting the hold.
        /// Strayed samples earn nothing.
        static let holdWobbleGrace = 0.25
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
    ///
    /// A brief loss of the torso keeps the hold (uncredited) and the last drawn pose, so one or
    /// two missed detections neither restart a hold nor flash the tracking-lost message.
    mutating func tick(_ time: Double) {
        guard let lastValid else {
            return
        }

        if time - lastValid > Limits.holdGrace {
            hold.clear()
            sustainedSince = nil
            snapshot.progress = 0
        }

        if time - lastValid > Limits.lostGrace {
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
        evidenceGap = false
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

    /// One side’s visible torso and optional knee; confidence selection uses the torso only.
    private func chain(
        in frame: TrackingObservation,
        left: Bool
    ) -> (joints: SitToStandJoints, score: Float, kneeIsReliable: Bool)? {
        let shoulderJoint: BodyJoint = left ? .leftShoulder : .rightShoulder
        let hipJoint: BodyJoint = left ? .leftHip : .rightHip
        let kneeJoint: BodyJoint = left ? .leftKnee : .rightKnee

        guard let shoulder = frame.point(shoulderJoint, minimumConfidence: Limits.confidence),
              let hip = frame.point(hipJoint, minimumConfidence: Limits.confidence) else {
            return nil
        }

        let knee = frame.point(kneeJoint, minimumConfidence: Limits.kneeConfidence)
        let kneeIsReliable = knee != nil
            && (frame.joints[kneeJoint]?.confidence ?? 0) >= Limits.reliableKneeConfidence
        let score = ((frame.joints[shoulderJoint]?.confidence ?? 0)
            + (frame.joints[hipJoint]?.confidence ?? 0)) / 2

        return (
            SitToStandJoints(shoulder: shoulder, hip: hip, knee: knee),
            score,
            kneeIsReliable
        )
    }

    /// Follow the torso side seen best, keeping it unless the other is clearly better so
    /// optional knee visibility cannot make the tracked torso flicker between sides.
    ///
    /// Once the seat is captured the side is fixed: the calibrated hip and shoulder belong to it,
    /// and the other side's hip sits at a different height in a side view, so switching would
    /// read as a rise or a drop that never happened. A missing calibrated side is missing evidence.
    private mutating func bestChain(
        in frame: TrackingObservation
    ) -> (joints: SitToStandJoints, kneeIsReliable: Bool)? {
        if seated != nil {
            return chain(in: frame, left: followsLeftLeg).map { ($0.joints, $0.kneeIsReliable) }
        }

        let left = chain(in: frame, left: true)
        let right = chain(in: frame, left: false)
        switch (left, right) {
        case (nil, nil):
            return nil
        case (let only?, nil):
            followsLeftLeg = true
            return (only.joints, only.kneeIsReliable)
        case (nil, let only?):
            followsLeftLeg = false
            return (only.joints, only.kneeIsReliable)
        case (let left?, let right?):
            let current = followsLeftLeg ? left : right
            let other = followsLeftLeg ? right : left
            if other.score > current.score + 0.15 {
                followsLeftLeg.toggle()
                return (other.joints, other.kneeIsReliable)
            }
            return (current.joints, current.kneeIsReliable)
        }
    }

    private func angle(at vertex: TherapyPoint, _ a: TherapyPoint, _ b: TherapyPoint) -> Double? {
        JointAngle.degrees(at: vertex, a, b)
    }

    private mutating func pose(in frame: TrackingObservation) -> Pose? {
        guard let (joints, kneeIsReliable) = bestChain(in: frame) else {
            return nil
        }

        let trunk = joints.shoulder - joints.hip
        guard trunk.length > Limits.minimumTrunk, trunk.y > 0 else {
            return nil
        }

        var thigh: Double?
        var hipAngle = 0.0
        if let knee = joints.knee {
            let thighVector = joints.hip - knee
            if thighVector.length > Limits.minimumThigh {
                hipAngle = angle(at: joints.hip, joints.shoulder, knee) ?? 0

                if kneeIsReliable {
                    thigh = atan2(thighVector.y, abs(thighVector.x)) * 180 / .pi
                }
            }

            let reach = knee.x - joints.hip.x
            if seated == nil, abs(reach) > 0.02 {
                forward = reach > 0 ? 1 : -1
            }
        }

        let lean = atan2(forward * trunk.x, trunk.y) * 180 / .pi
        return Pose(
            joints: joints,
            thigh: thigh,
            hipAngle: hipAngle,
            scale: trunk.length,
            lean: lean
        )
    }

    /// Hip travel is continuous even when the optional knee enters or leaves the image.
    private func rise(of pose: Pose, seated: Pose, standing: Pose) -> Double {
        let span = max(0.01, hipRise(of: standing, from: seated))
        return clamped(hipRise(of: pose, from: seated) / span)
    }

    private func hipRise(of pose: Pose, from seated: Pose) -> Double {
        (pose.joints.hip.y - seated.joints.hip.y) / seated.scale
    }

    private func shoulderRise(of pose: Pose, from seated: Pose) -> Double {
        (pose.joints.shoulder.y - seated.joints.shoulder.y) / seated.scale
    }

    /// Leaning or changing apparent torso size alone cannot establish the standing endpoint.
    private func standingTorso(_ pose: Pose, from seated: Pose) -> Bool {
        Limits.standingTrunkScale.contains(pose.scale / seated.scale)
            && abs(pose.lean) <= Limits.maximumStandingLean
            && shoulderRise(of: pose, from: seated) >= Limits.minimumHeightGain
    }

    // MARK: - Observation

    private mutating func consume(_ frame: TrackingObservation) {
        let time = frame.timestamp
        guard time.isFinite, last.map({ time > $0 }) ?? true else {
            interrupt()
            return
        }
        let gap = last.map { time - $0 } ?? 0

        // Dwells measure wall time, so a camera stall restarts them; holds keep their own gap
        // rule (`consumeHold`), which keeps them alive but never credits the stall.
        if gap > Limits.holdStep {
            sustainedSince = nil
        }

        if gap > Limits.holdGrace {
            hold.clear()
        }

        if gap > Limits.lostGrace {
            resetRepetition()
            awaitingSeat = standing != nil
        }

        last = time

        if time > cueExpiresAt {
            snapshot.cue = nil
        }

        guard let current = pose(in: frame) else {
            noteMissingTorso()
            return
        }

        defer {
            evidenceGap = false
        }

        snapshot.trackingMessage = nil

        if lastValid.map({ time - $0 > Limits.lostGrace }) == true {
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

    /// A frame without the calibrated side's shoulder and hip. Nothing advances or is credited,
    /// but a hold in progress and the drawn pose survive a brief loss: `tick` clears the hold
    /// after `holdGrace` and shows the tracking-lost message after `lostGrace`. Before the
    /// patient has ever been seen there is nothing to keep, so the message shows at once.
    private mutating func noteMissingTorso() {
        evidenceGap = true
        sustainedSince = nil

        guard lastValid == nil else {
            return
        }

        hold.clear()
        snapshot.progress = 0
        snapshot.joints = nil
        snapshot.guide = nil
        snapshot.trackingMessage = "sts.trackingLost"
    }

    /// Adds one fresh sample to the current hold. A sample after a frame without torso
    /// evidence keeps the hold alive (within `holdGrace`) but earns nothing for that interval,
    /// so only time between consecutive observed samples is credited.
    private mutating func consumeHold(_ current: Pose, time: Double, duration: Double) {
        hold.consume(
            current.joints.hip,
            time: time,
            duration: duration,
            tolerance: current.scale * Limits.holdTolerance,
            maximumGap: Limits.holdGrace,
            creditedStep: evidenceGap ? 0 : Limits.holdStep,
            wobbleGrace: Limits.holdWobbleGrace
        )
    }

    /// `pose` with its hip replaced by a hold's mean hip, so a calibrated reference is the
    /// whole held position rather than whichever single frame ended the hold.
    private func pose(_ pose: Pose, heldHip: TherapyPoint?) -> Pose {
        guard let heldHip else {
            return pose
        }

        var joints = pose.joints
        joints.hip = heldHip

        return Pose(
            joints: joints,
            thigh: pose.thigh,
            hipAngle: pose.hipAngle,
            scale: pose.scale,
            lean: pose.lean
        )
    }

    // MARK: - Calibration

    /// The starting position: a comfortable seat held still. Completing it pops the hip circle.
    private mutating func captureSeated(_ current: Pose, time: Double) {
        snapshot.guide = nil

        let seatedHere = current.thigh.map { Limits.seatedThigh.contains($0) } ?? true
        let ready = seatedHere && abs(current.lean) <= Limits.maximumSeatedLean

        guard ready else {
            hold.clear()
            publish(hold: Limits.seatedHold, instruction: "sts.sitDown")
            return
        }

        consumeHold(current, time: time, duration: Limits.seatedHold)
        publish(hold: Limits.seatedHold, instruction: "sts.holdSeated")

        guard hold.progress >= 1 else {
            return
        }

        seated = pose(current, heldHip: hold.mean)
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

        let heightGain = hipRise(of: current, from: seated)

        recordTrialPeak(current, seated: seated, heightGain: heightGain, time: time)

        guard trial.reachedStand else {
            snapshot.instruction = "sts.holdStanding"
            snapshot.guide = standUpGuide(current, seated: seated, standing: nil)
            hold.clear()
            sustainedSince = nil
            return
        }

        holdStandingPose(current, seated: seated, heightGain: heightGain, time: time)
        snapshot.guide = trialGuide(current, seated: seated)

        guard trial.standHeld else {
            sustainedSince = nil
            return
        }

        let settledHeight = heightGain <= trial.maxHeightGain * Limits.trialSeatedFraction

        guard sustainedFor(settledHeight, at: time, seconds: Limits.trialSettle),
              let best = trial.bestPose
        else {
            return
        }

        standing = pose(best, heldHip: trial.heldHip)
        returningBeforePractice = true
        awaitingSeat = true
        sustainedSince = nil
        snapshot.instruction = "sts.sitDown"
    }

    /// A peak needs both visible torso landmarks to rise, with a plausible upright trunk.
    private mutating func recordTrialPeak(
        _ current: Pose,
        seated: Pose,
        heightGain: Double,
        time: Double
    ) {
        guard heightGain >= Limits.minimumHeightGain,
              standingTorso(current, from: seated) else {
            return
        }

        if heightGain > trial.maxHeightGain + Limits.peakMargin || !trial.reachedStand {
            trial.peakRaisedAt = time
        }

        if heightGain > trial.maxHeightGain {
            trial.maxHeightGain = heightGain
            trial.bestPose = current
        }
        trial.reachedStand = true
    }

    /// Counts down while the patient stays still at the top of their stand, so the standing pose
    /// is as deliberate as the seated one. Sitting before it completes asks them to stand again.
    private mutating func holdStandingPose(_ current: Pose, seated: Pose, heightGain: Double, time: Double) {
        guard !trial.standHeld else {
            snapshot.instruction = "sts.sitDown"
            return
        }

        let nearPeak = heightGain >= trial.maxHeightGain * Limits.standingPeakFraction
            && standingTorso(current, from: seated)

        guard nearPeak else {
            hold.clear()
            snapshot.instruction = "sts.holdStanding"
            return
        }

        // Start the hold only once the hip has stopped rising, so the arc fills from the arrival
        // instead of starting mid-rise and restarting as the hip leaves its first position. A
        // hold already running is kept; its tolerance handles any later drift.
        let arrived = time - trial.peakRaisedAt >= Limits.arrivalSettle

        guard hold.isActive || arrived else {
            snapshot.instruction = "sts.holdStanding"
            return
        }

        consumeHold(current, time: time, duration: Limits.standingHold)
        publish(hold: Limits.standingHold, instruction: "sts.holdStanding")

        guard hold.progress >= 1 else {
            return
        }

        trial.standHeld = true
        trial.heldHip = hold.mean
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

            if sustained(rise >= Limits.standingRise && standingTorso(current, from: seated), at: time) {
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
            // Starts empty at the seated threshold, as the lowering half ends there, so sitting
            // jitter and the settle after a count never show a sliver of arc.
            let ascent = (rise - Limits.seatedRise) / (Limits.standingRise - Limits.seatedRise)
            snapshot.repetitionProgress = clamped(ascent)
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
