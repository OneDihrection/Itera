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
/// The guided session engine and the Balancing session feed it gated observations with the
/// activity's count. A repetition spans the frames between two increases of that count, so it
/// follows the activity's own acceptance. Guided arm exercises derive their angle from the
/// recorded joints; Balancing engines supply their own estimate, which the recorder keeps. Work stays bounded: frames are thinned
/// to `sampleInterval`, one repetition keeps at most `maximumRepSeconds`, and at most three
/// skeletons are held at once.
struct KeyRepRecorder {
    static let sampleInterval = 1.0 / 15
    static let maximumRepSeconds = 30.0
    /// Peaks closer than this are treated as equal when choosing the hardest repetition.
    private static let peakTolerance = 1.0

    private struct Sample {
        let timestamp: Double
        let joints: [BodyJoint: TherapyPoint]
        let suppliedAngle: Double?
        let side: TherapySide?
    }

    private let activity: SessionActivity
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
        self.activity = activity
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
        append(frame, angle: angle, side: side, force: completesRep)

        guard completesRep else {
            return nil
        }

        return completeRep(number: count)
    }

    /// Drops the repetition in progress, for pauses, camera waits and recalibration.
    /// Completed repetitions are kept.
    mutating func discardCurrentRep() {
        samples.removeAll(keepingCapacity: true)
        repStart = nil
    }

    // MARK: - Output

    /// The recorded key repetitions, or nil when no repetition was completed.
    func keyReps(executionID: UUID, setNumber: Int) -> ActivityKeyReps? {
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

    // MARK: - Recording

    /// Movement and reach count only in practice; rehearsal and timed practice are not repetitions.
    private func isCountedPractice(_ presentation: ActivityPresentation) -> Bool {
        switch presentation {
        case .movement(let value):
            return value.phase == .practice
        case .reach(let value):
            return value.phase == .practice && !value.rehearsal
        case .towel, .timed:
            return false
        }
    }

    private mutating func append(_ frame: TrackingObservation, angle: Double?, side: TherapySide?, force: Bool) {
        if let previous = samples.last,
           !force,
           frame.timestamp - previous.timestamp < Self.sampleInterval
        {
            return
        }

        if repStart == nil {
            repStart = frame.timestamp
        }

        aspect = frame.aspect
        samples.append(
            Sample(
                timestamp: frame.timestamp,
                joints: usableJoints(in: frame),
                suppliedAngle: angle.flatMap { $0.isFinite ? $0 : nil },
                side: side
            )
        )

        // A stalled repetition keeps only its latest seconds, so memory stays bounded.
        let oldest = frame.timestamp - Self.maximumRepSeconds
        if let first = samples.first, first.timestamp < oldest {
            samples.removeAll { $0.timestamp < oldest }
        }
    }

    private func usableJoints(in frame: TrackingObservation) -> [BodyJoint: TherapyPoint] {
        guard frame.personCount == 1 else {
            return [:]
        }

        var joints: [BodyJoint: TherapyPoint] = [:]

        for joint in BodyJoint.allCases {
            // `point` applies the shared confidence and bounds rules but returns aspect-corrected x.
            guard let point = frame.point(joint) else {
                continue
            }

            joints[joint] = TherapyPoint(x: point.x / frame.aspect, y: point.y)
        }

        return joints
    }

    private mutating func completeRep(number: Int) -> KeyRepClipRequest? {
        guard let start = repStart,
              let end = samples.last?.timestamp,
              let origin = samples.first?.timestamp
        else {
            return nil
        }

        let angles = samples.map(angle(in:))
        let tracked = samples.filter(isTracked).count

        let repMetrics = RepMetrics(
            repNumber: number,
            duration: end - start,
            startAngle: Self.median(of: angles.compactMap { $0 }.prefix(3)),
            peakAngle: Self.median(of: angles.compactMap { $0 }.sorted().suffix(3)),
            trackingCoverage: Double(tracked) / Double(samples.count),
            side: samples.last?.side
        )
        metrics.append(repMetrics)

        let rep = KeyRep(
            roles: [],
            metrics: repMetrics,
            aspectRatio: aspect,
            frames: samples.map {
                SkeletonFrame(time: $0.timestamp - origin, joints: $0.joints)
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

    /// The lower peak is harder; similar peaks, or reps without angles, fall back to the slower rep.
    private func isHarder(_ candidate: KeyRep, than current: KeyRep) -> Bool {
        if let candidatePeak = candidate.metrics.peakAngle,
           let currentPeak = current.metrics.peakAngle,
           abs(candidatePeak - currentPeak) > Self.peakTolerance
        {
            return candidatePeak < currentPeak
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

    /// Balancing engines estimate their own angle (rotation, knee extension); cross-midline has none.
    private var suppliesAngle: Bool {
        switch activity.kind {
        case .externalRotation, .internalRotation, .shoulderFlexion, .sitToStand:
            return true
        case .armRaise, .elbowBend, .directionalReach, .foldTowel, .crossMidline:
            return false
        }
    }

    /// A frame counts as tracked when the exercise's measurement was usable in it.
    private func isTracked(_ sample: Sample) -> Bool {
        if suppliesAngle {
            return sample.suppliedAngle != nil
        }

        let arm = ArmChain(sample.side ?? activity.side)
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

        return required.allSatisfy { sample.joints[$0] != nil }
    }

    /// Arm raise uses hip–shoulder–elbow and elbow bend uses shoulder–elbow–wrist, the same
    /// chains the activities score. Elbow bend reports flexion, so a larger value is more bend.
    /// Balancing exercises use the angle their engine supplied.
    private func angle(in sample: Sample) -> Double? {
        if suppliesAngle {
            return sample.suppliedAngle
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
