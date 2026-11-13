//
//  KeyRepRecorder.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import Foundation

/// Records per-repetition metrics and keeps the skeletons of three key repetitions of a set:
/// the first, the hardest and the last.
///
/// The guided session engine, the Balancing session and the finger session feed it gated
/// observations with the activity's count. A repetition spans the frames between two increases
/// of that count, so it follows the activity's own acceptance. Guided arm exercises derive their
/// angle from the recorded joints; Balancing engines supply their own estimate, and finger
/// exercises supply the share of their calibrated range, which the recorder keeps. Fold towel
/// and finger exercises record the hand instead of the body. Work stays bounded: frames are
/// thinned to `sampleInterval`, one repetition keeps at most `maximumRepSeconds`, and at most
/// three skeletons are held at once.
struct KeyRepRecorder {
    static let sampleInterval = 1.0 / 15
    /// Long enough for a full directional-reach round or a slow four-fold towel;
    /// `RepClipFrameSource` keeps a longer ring.
    static let maximumRepSeconds = 60.0
    /// Peaks closer than this are treated as equal when choosing the hardest repetition.
    private static let peakTolerance = 1.0
    /// Range fractions closer than this are treated as equal when choosing the hardest repetition.
    private static let fractionTolerance = 0.02
    /// Hand joints below this confidence are recorded as missing.
    private static let handConfidence: Float = 0.3
    /// Body joints are kept down to this confidence, so a replay loses as little of the movement
    /// as possible. Whether a frame counts as tracked is judged separately, at the exercise's
    /// own scoring floors (`scoringFloor(for:kind:)`).
    private static let recordingConfidence: Float = 0.1

    private struct Sample {
        let timestamp: Double
        let joints: [BodyJoint: TherapyPoint]
        let hand: [TherapyPoint?]?
        /// The joints the measurement needs were usable at the exercise's scoring floors.
        let tracked: Bool
        let suppliedAngle: Double?
        let suppliedFraction: Double?
        let side: TherapySide?
    }

    private let subject: KeyRepSubject
    /// Identifies this recorder's set to the clip source, so a set's clips can still be taken
    /// after the next set has begun keeping its own.
    let clipGroup = UUID()
    private var samples: [Sample] = []
    private var repStart: Double?
    private var aspect = 1.0
    /// The count already seen; nil until the first observation, so a set that does not start
    /// at zero never credits its existing count as a new repetition.
    private var lastCount: Int?
    private var first: KeyRep?
    private var hardest: KeyRep?
    private var last: KeyRep?
    private(set) var metrics: [RepMetrics] = []

    init(activity: SessionActivity) {
        subject = .activity(activity)
    }

    init(subject: KeyRepSubject) {
        self.subject = subject
    }

    // MARK: - Input

    /// Records a guided-session frame, reading counted practice and the count from `presentation`.
    @discardableResult
    mutating func observe(_ frame: TrackingObservation, presentation: ActivityPresentation) -> KeyRepClipRequest? {
        observe(frame, counted: isCountedPractice(presentation), count: presentation.count)
    }

    /// Records `frame` while `counted`, closing a repetition whenever `count` increases. Anything
    /// else discards the unfinished repetition.
    /// - Parameters:
    ///   - angle: The engine's own movement angle for this frame, in degrees, when it has one.
    ///   - side: The arm moving in this frame, for exercises where both arms take turns.
    /// - Returns: The clip to keep when this frame completed a repetition.
    @discardableResult
    mutating func observe(
        _ frame: TrackingObservation,
        counted: Bool,
        count: Int,
        angle: Double? = nil,
        side: TherapySide? = nil
    ) -> KeyRepClipRequest? {
        // A local copy, so the sample can be built while `advance` mutates the recorder.
        let activity = activity

        return advance(counted: counted, count: count, timestamp: frame.timestamp, aspect: frame.aspect) {
            Sample(
                timestamp: frame.timestamp,
                joints: Self.usableJoints(in: frame, minimumConfidence: Self.recordingConfidence),
                hand: frame.hand.flatMap(Self.handPoints),
                tracked: Self.measuredJointsTracked(in: frame, activity: activity, side: side),
                suppliedAngle: angle.flatMap { $0.isFinite ? $0 : nil },
                suppliedFraction: nil,
                side: side
            )
        }
    }

    /// Records a finger-exercise frame, as `observe(_:counted:count:angle:side:)` does for bodies.
    /// - Parameter fraction: The repetition's reached share of the calibrated range, once known.
    @discardableResult
    mutating func observe(
        hand: HandEvidence,
        counted: Bool,
        count: Int,
        fraction: Double?
    ) -> KeyRepClipRequest? {
        advance(counted: counted, count: count, timestamp: hand.timestamp, aspect: hand.width / max(hand.height, 1)) {
            Sample(
                timestamp: hand.timestamp,
                joints: [:],
                hand: Self.handPoints(hand),
                tracked: false,
                suppliedAngle: nil,
                suppliedFraction: fraction.flatMap { $0.isFinite ? $0 : nil },
                side: nil
            )
        }
    }

    /// Drops the repetition in progress, for pauses, camera waits and recalibration.
    /// Completed repetitions are kept.
    mutating func discardCurrentRep() {
        samples.removeAll(keepingCapacity: true)
        repStart = nil
    }

    // MARK: - Output

    /// The recorded key repetitions of a guided or Balancing activity, or nil when no
    /// repetition was completed.
    func keyReps(executionID: UUID, setNumber: Int) -> ActivityKeyReps? {
        guard case .activity(let activity) = subject else {
            return nil
        }

        let reps = keptReps()

        guard !reps.isEmpty else {
            return nil
        }

        return ActivityKeyReps(
            executionID: executionID,
            activity: activity,
            setNumber: setNumber,
            reps: reps,
            clipGroup: clipGroup
        )
    }

    /// The recorded key repetitions of a finger exercise, or nil when no repetition was completed.
    func fingerKeyReps(setNumber: Int) -> FingerKeyReps? {
        guard case .finger(let exercise, _) = subject else {
            return nil
        }

        let reps = keptReps()

        guard !reps.isEmpty else {
            return nil
        }

        return FingerKeyReps(exercise: exercise, setNumber: setNumber, reps: reps, clipGroup: clipGroup)
    }

    /// First, hardest and last, with one repetition holding every role it earned.
    private func keptReps() -> [KeyRep] {
        var reps: [KeyRep] = []

        for (role, candidate) in [(KeyRepRole.first, first), (.hardest, hardest), (.last, last)] {
            guard let candidate else {
                continue
            }

            if let index = reps.firstIndex(where: { $0.metrics.repNumber == candidate.metrics.repNumber }) {
                reps[index].roles.append(role)
            } else {
                var rep = candidate
                rep.roles = [role]
                reps.append(rep)
            }
        }

        return reps
    }

    // MARK: - Recording

    /// Movement, reach and towel count only in practice; rehearsal and timed practice are not
    /// repetitions.
    private func isCountedPractice(_ presentation: ActivityPresentation) -> Bool {
        switch presentation {
        case .movement(let value):
            return value.phase == .practice
        case .reach(let value):
            // The observation that credits the set's last round also finishes the activity, so
            // it arrives as `.finished` and must still close that round.
            return !value.rehearsal && (value.phase == .practice || value.phase == .finished)
        case .towel(let value):
            return value.phase == .practice
        case .timed:
            return false
        }
    }

    /// Shared counting: closes a repetition whenever `count` increases while `counted`.
    private mutating func advance(
        counted: Bool,
        count: Int,
        timestamp: Double,
        aspect: Double,
        sample: () -> Sample
    ) -> KeyRepClipRequest? {
        guard counted else {
            discardCurrentRep()
            lastCount = count
            return nil
        }

        let previous = lastCount ?? count

        if count < previous {
            discardCurrentRep()
        }

        let completesRep = count > previous
        lastCount = count
        append(timestamp: timestamp, aspect: aspect, force: completesRep, sample: sample)

        guard completesRep else {
            return nil
        }

        return completeRep(number: count)
    }

    private mutating func append(timestamp: Double, aspect: Double, force: Bool, sample: () -> Sample) {
        if let previous = samples.last,
           !force,
           timestamp - previous.timestamp < Self.sampleInterval
        {
            return
        }

        if repStart == nil {
            repStart = timestamp
        }

        self.aspect = aspect
        samples.append(sample())

        // A stalled repetition keeps only its latest seconds, so memory stays bounded.
        let oldest = timestamp - Self.maximumRepSeconds
        if let first = samples.first, first.timestamp < oldest {
            samples.removeAll { $0.timestamp < oldest }
        }
    }

    private static func usableJoints(
        in frame: TrackingObservation,
        minimumConfidence: Float
    ) -> [BodyJoint: TherapyPoint] {
        guard frame.personCount == 1 else {
            return [:]
        }

        var joints: [BodyJoint: TherapyPoint] = [:]

        for joint in BodyJoint.allCases {
            // `point` applies the confidence and bounds rules but returns aspect-corrected x.
            guard let point = frame.point(joint, minimumConfidence: minimumConfidence) else {
                continue
            }

            joints[joint] = TherapyPoint(x: point.x / frame.aspect, y: point.y)
        }

        return joints
    }

    /// The hand's joints in unmirrored normalized space, or nil when no joint is usable.
    private static func handPoints(_ hand: HandEvidence) -> [TherapyPoint?]? {
        guard hand.points.count == SkeletonFrame.handJointCount else {
            return nil
        }

        let points = hand.points.map { point -> TherapyPoint? in
            guard point.confidence >= handConfidence,
                  point.x.isFinite,
                  point.y.isFinite
            else {
                return nil
            }

            return TherapyPoint(x: point.x, y: point.y)
        }

        return points.contains { $0 != nil } ? points : nil
    }

    private mutating func completeRep(number: Int) -> KeyRepClipRequest? {
        guard let start = repStart,
              let end = samples.last?.timestamp,
              let origin = samples.first?.timestamp
        else {
            return nil
        }

        // Angles come only from frames the exercise could score, so a faint joint kept for the
        // replay can never set a start or peak.
        let angles = samples.map { isTracked($0) ? angle(in: $0) : nil }
        let tracked = samples.filter(isTracked).count

        let repMetrics = RepMetrics(
            repNumber: number,
            duration: end - start,
            startAngle: Self.median(of: angles.compactMap { $0 }.prefix(3)),
            peakAngle: Self.median(of: angles.compactMap { $0 }.sorted().suffix(3)),
            trackingCoverage: Double(tracked) / Double(samples.count),
            side: samples.last?.side,
            // The activity reports the repetition's reached range once its target holds commit,
            // so the latest value is the repetition's own.
            peakFraction: samples.last { $0.suppliedFraction != nil }?.suppliedFraction
        )
        metrics.append(repMetrics)

        let rep = KeyRep(
            roles: [],
            metrics: repMetrics,
            aspectRatio: aspect,
            frames: samples.map {
                SkeletonFrame(time: $0.timestamp - origin, joints: $0.joints, hand: $0.hand)
            }
        )

        if first == nil {
            first = rep
        }

        if hardest.map({ isHarder(rep, than: $0) }) ?? true {
            hardest = rep
        }

        last = rep
        discardCurrentRep()

        return KeyRepClipRequest(
            group: clipGroup,
            repNumber: number,
            start: origin,
            end: end,
            retaining: Set([first, hardest, last].compactMap { $0?.metrics.repNumber })
        )
    }

    // MARK: - Metrics

    /// The lower peak angle, or else the smaller share of the calibrated range, is harder;
    /// similar values, or reps without either, fall back to the slower rep.
    private func isHarder(_ candidate: KeyRep, than current: KeyRep) -> Bool {
        if let candidatePeak = candidate.metrics.peakAngle,
           let currentPeak = current.metrics.peakAngle,
           abs(candidatePeak - currentPeak) > Self.peakTolerance
        {
            return candidatePeak < currentPeak
        }

        if let candidateFraction = candidate.metrics.peakFraction,
           let currentFraction = current.metrics.peakFraction,
           abs(candidateFraction - currentFraction) > Self.fractionTolerance
        {
            return candidateFraction < currentFraction
        }

        return candidate.metrics.duration > current.metrics.duration
    }

    private struct ArmChain {
        let shoulder: BodyJoint
        let elbow: BodyJoint
        let wrist: BodyJoint
        let hip: BodyJoint

        init(_ side: TherapySide) {
            switch side {
            case .left:
                (shoulder, elbow, wrist, hip) = (.leftShoulder, .leftElbow, .leftWrist, .leftHip)
            case .right:
                (shoulder, elbow, wrist, hip) = (.rightShoulder, .rightElbow, .rightWrist, .rightHip)
            }
        }
    }

    /// The body activity being recorded; nil for finger exercises.
    private var activity: SessionActivity? {
        guard case .activity(let activity) = subject else {
            return nil
        }

        return activity
    }

    /// Balancing engines estimate their own angle (rotation, knee extension); cross-midline has none.
    private var suppliesAngle: Bool {
        switch activity?.kind {
        case .externalRotation, .internalRotation, .shoulderFlexion, .sitToStand:
            return true
        case .armRaise, .elbowBend, .directionalReach, .foldTowel, .crossMidline, nil:
            return false
        }
    }

    /// A frame counts as tracked when the exercise's measurement was usable in it.
    private func isTracked(_ sample: Sample) -> Bool {
        if suppliesAngle {
            return sample.suppliedAngle != nil
        }

        guard let activity, activity.kind != .foldTowel else {
            return sample.hand != nil
        }

        return sample.tracked
    }

    /// Whether the joints the exercise measures are usable in `frame` at its scoring floors.
    private static func measuredJointsTracked(
        in frame: TrackingObservation,
        activity: SessionActivity?,
        side: TherapySide?
    ) -> Bool {
        guard let activity else {
            return false
        }

        let arm = ArmChain(side ?? activity.side)
        let required: [BodyJoint]

        switch activity.kind {
        case .armRaise:
            required = [arm.hip, arm.shoulder, arm.elbow]
        case .elbowBend:
            required = [arm.shoulder, arm.elbow, arm.wrist]
        case .directionalReach, .crossMidline:
            required = [.leftShoulder, .rightShoulder, arm.wrist]
        case .foldTowel, .sitToStand, .externalRotation, .internalRotation, .shoulderFlexion:
            required = []
        }

        return required.allSatisfy { joint in
            frame.point(joint, minimumConfidence: scoringFloor(for: joint, kind: activity.kind)) != nil
        }
    }

    /// The confidence each exercise scores a joint at. These mirror the activities'
    /// own floors (`MovementActivity`, `CrossMidlineBalanceEngine`, `SitToStandActivity`,
    /// `ArmMovementEngine`, `DirectionalReachActivity`) and must change with them.
    private static func scoringFloor(for joint: BodyJoint, kind: TherapyKind) -> Float {
        let limb = [.leftElbow, .rightElbow, .leftWrist, .rightWrist].contains(joint)

        switch kind {
        case .armRaise, .elbowBend:
            return limb ? 0.2 : 0.3
        case .crossMidline:
            return 0.2
        case .sitToStand:
            return 0.3
        case .externalRotation, .internalRotation, .shoulderFlexion:
            return limb ? 0.1 : 0.3
        case .directionalReach, .foldTowel:
            return 0.5
        }
    }

    /// Arm raise uses hip–shoulder–elbow and elbow bend uses shoulder–elbow–wrist, the same
    /// chains the activities score. Elbow bend reports flexion, so a larger value is more bend.
    /// Balancing exercises use the angle their engine supplied. Hand exercises have no angle.
    private func angle(in sample: Sample) -> Double? {
        if suppliesAngle {
            return sample.suppliedAngle
        }

        guard let activity else {
            return nil
        }

        let arm = ArmChain(sample.side ?? activity.side)
        let point: (BodyJoint) -> TherapyPoint? = { joint in
            sample.joints[joint].map { TherapyPoint(x: $0.x * aspect, y: $0.y) }
        }

        switch activity.kind {
        case .armRaise:
            guard let hip = point(arm.hip),
                  let shoulder = point(arm.shoulder),
                  let elbow = point(arm.elbow)
            else {
                return nil
            }

            return JointAngle.degrees(at: shoulder, hip, elbow)
        case .elbowBend:
            guard let shoulder = point(arm.shoulder),
                  let elbow = point(arm.elbow),
                  let wrist = point(arm.wrist),
                  let interior = JointAngle.degrees(at: elbow, shoulder, wrist)
            else {
                return nil
            }

            return 180 - interior
        case .directionalReach, .foldTowel, .sitToStand, .crossMidline,
             .externalRotation, .internalRotation, .shoulderFlexion:
            return nil
        }
    }

    /// The median of a few samples, so one noisy frame cannot set a start or a peak.
    private static func median<Values: Collection<Double>>(of values: Values) -> Double? {
        let sorted = values.sorted()

        guard !sorted.isEmpty else {
            return nil
        }

        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }

        return sorted[middle]
    }
}
