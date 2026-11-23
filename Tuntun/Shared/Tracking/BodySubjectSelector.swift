//
//  BodySubjectSelector.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import Foundation

/// Chooses which detected person is the patient when others are in view.
///
/// The patient sits facing the iPad and stays in roughly one place, while bystanders walk
/// through. Selection prefers, in order:
/// 1. **Continuity**: the person whose torso is nearest the patient's recently tracked torso,
///    at a similar size, and, when several people are in view, still near the patient's usual
///    place. A sole person is followed by continuity alone, so standing up keeps the lock.
/// 2. **Usual place**: after a longer loss (someone walked in front), only a person back at
///    the remembered seat and size is picked up again, never simply the largest person. When
///    only one person is in view, a wider size range is accepted, so leaning toward the iPad
///    does not lose the patient.
/// 3. **First pick**: before any place is known, or once the patient has been missing for
///    `relockTimeout`, a person clearly larger than everyone else, or, among people of similar
///    size, the one clearly nearest the centre of the frame, where setup places the patient.
///    Position only breaks ties; it never decides alone.
///
/// When no rule settles it, no subject is reported, so exercises pause rather than follow a
/// stranger. Anatomical sides always come from the selected person's own landmarks, never
/// from screen position.
struct BodySubjectSelector {
    struct Candidate {
        /// Aspect-corrected mean of the confident torso joints. Not finite when the person has
        /// no confident torso joint and so cannot be followed.
        let torso: TherapyPoint
        /// Aspect-corrected shoulder width, or 0 when a shoulder is not confidently visible.
        /// Arm movement does not change it, so it reliably tells a nearer bystander from the
        /// seated patient. An unknown size never rejects a candidate; position still must match.
        let size: Double
        /// Horizontal distance of the torso from the frame's centre, 0 to 0.5.
        var centerOffset: Double = 0.5
    }

    /// Which rule settled the latest frame, for diagnostics.
    enum Decision: String {
        case continuity
        case anchored
        case initial
        /// Someone could be followed, but no rule picked them.
        case ambiguous
        /// Nobody in view had a confident torso.
        case noTrackable
    }

    /// How long a lost patient remains the preferred subject. Matches the exercise hold grace.
    static let continuityWindow = 1.5
    /// How long the patient's usual place is remembered after tracking is lost. Afterwards the
    /// first-pick rules apply again, so a missed re-acquisition cannot hide the patient for long.
    static let relockTimeout = 5.0
    /// How much more centred the patient must be than everyone else to win a first-pick tie.
    private static let centeringMargin = 0.12
    private static let dominanceRatio = 1.4
    private static let sizeRange = 0.7...1.45
    /// Stricter size match when picking the patient up again at their usual place.
    private static let anchorSizeRange = 0.75...1.33
    /// Wider size match when the only person in view sits at the usual place: leaning toward the
    /// iPad to reach grows the shoulders, while someone hiding the patient is much nearer.
    private static let soleCandidateSizeRange = 0.6...1.8
    /// Shoulder-width difference, in image heights, that is always treated as landmark jitter
    /// (about 5 cm at 1 m). Only decides between small sizes, such as a side view.
    private static let sizeNoise = 0.03
    /// The capture rate the continuity gate is defined for.
    private static let nominalFrameRate = 30.0
    /// The most camera frames the continuity gate widens for, so a long gap is not a free pass.
    private static let maximumGateFrames = 3.0
    /// How quickly the usual place follows the tracked patient. Slow, so reaching across the
    /// body during an exercise does not drag the remembered seat with the arm.
    private static let anchorFollowRate = 0.05

    private var lastTorso: TherapyPoint?
    private var lastSize = 0.0
    private var lastTime: Double?
    private var anchorTorso: TherapyPoint?
    private var anchorSize = 0.0
    private var anchorTime: Double?
    private var generation: UUID?

    /// Increments whenever the subject is picked without frame-to-frame continuity (first pick
    /// or pick-up at the usual place), so landmark smoothing never blends two people.
    private(set) var epoch = 0

    /// The rule that settled the latest `select` call.
    private(set) var lastDecision = Decision.noTrackable

    /// Seconds since the usual place was last refreshed, or nil when none is remembered.
    func anchorAge(at time: Double) -> Double? {
        anchorTime.map { time - $0 }
    }

    /// Forgets the patient. A new camera generation (restart, camera or orientation change)
    /// means positions are no longer comparable.
    mutating func reset() {
        lastTorso = nil
        lastSize = 0
        lastTime = nil
        anchorTorso = nil
        anchorSize = 0
        anchorTime = nil
        generation = nil
    }

    /// - Returns: the index of the patient in `candidates`, or `nil` when ambiguous.
    mutating func select(_ candidates: [Candidate], at time: Double, generation: UUID) -> Int? {
        if self.generation != generation {
            reset()
            self.generation = generation
        }

        // A person without a torso can never be followed, so they never take part.
        let trackable = candidates.indices.filter {
            candidates[$0].torso.x.isFinite && candidates[$0].torso.y.isFinite
        }

        guard !trackable.isEmpty else {
            lastDecision = .noTrackable
            return nil
        }

        if let continuing = continuingIndex(in: candidates, among: trackable, at: time) {
            lastDecision = .continuity
            remember(candidates[continuing], at: time)
            return continuing
        }

        let found: Int?

        if let anchored = anchoredIndex(in: candidates, among: trackable, at: time) {
            lastDecision = .anchored
            found = anchored
        } else if let initial = initialIndex(in: candidates, among: trackable, at: time) {
            lastDecision = .initial
            found = initial
        } else {
            lastDecision = .ambiguous
            found = nil
        }

        guard let index = found else {
            return nil
        }

        // The track was broken, so earlier landmarks may belong to someone else.
        epoch += 1
        remember(candidates[index], at: time)
        return index
    }

    // MARK: - Rules

    private func continuingIndex(in candidates: [Candidate], among trackable: [Int], at time: Double) -> Int? {
        guard let lastTorso,
              let lastTime,
              time - lastTime <= Self.continuityWindow else {
            return nil
        }

        // A seated patient's torso moves well under half a body-size between tracked frames.
        // The gate is per camera frame (1/30 s): after skipped inference frames the patient may
        // have moved further, so it widens with the elapsed frames, up to three.
        let elapsedFrames = min(
            Self.maximumGateFrames,
            max(1, (time - lastTime) * Self.nominalFrameRate)
        )
        let gate = max(0.08, lastSize * 0.5) * elapsedFrames

        // The usual place only decides between several people. With one person in view,
        // frame-to-frame continuity alone keeps the lock, so standing up (the torso rises about
        // a trunk length, faster than the slow anchor follows) does not drop the patient.
        let arbitratesByPlace = trackable.count > 1

        let nearest = trackable
            .filter { Self.sizeMatches(candidates[$0].size, reference: lastSize, range: Self.sizeRange) }
            .filter { matchesAnchorSize(candidates[$0], range: Self.anchorSizeRange, at: time) }
            .filter { !arbitratesByPlace || isNearAnchor(candidates[$0], at: time, gateScale: 1.5) }
            .map { (index: $0, distance: (candidates[$0].torso - lastTorso).length) }
            .min { $0.distance < $1.distance }

        guard let nearest, nearest.distance <= gate else {
            return nil
        }

        return nearest.index
    }

    /// After a longer loss, only someone back at the patient's usual place and size.
    private func anchoredIndex(in candidates: [Candidate], among trackable: [Int], at time: Double) -> Int? {
        guard let anchorTorso, hasAnchor(at: time) else {
            return nil
        }

        let sizeRange = trackable.count == 1 ? Self.soleCandidateSizeRange : Self.anchorSizeRange

        let nearest = trackable
            .filter { matchesAnchorSize(candidates[$0], range: sizeRange, at: time) }
            .filter { isNearAnchor(candidates[$0], at: time, gateScale: 1) }
            .map { (index: $0, distance: (candidates[$0].torso - anchorTorso).length) }
            .min { $0.distance < $1.distance }

        return nearest?.index
    }

    /// Only before the patient's place is known; afterwards a stranger is never picked by size.
    private func initialIndex(in candidates: [Candidate], among trackable: [Int], at time: Double) -> Int? {
        guard !hasAnchor(at: time) else {
            return nil
        }

        let sizes = trackable.map { candidates[$0].size }

        if let dominant = dominantSubjectIndex(sizes: sizes, ratio: Self.dominanceRatio) {
            return trackable[dominant]
        }

        return centredIndex(in: candidates, among: trackable)
    }

    /// Among similarly sized people, the one clearly nearest the centre of the frame.
    private func centredIndex(in candidates: [Candidate], among trackable: [Int]) -> Int? {
        let ranked = trackable.sorted { candidates[$0].centerOffset < candidates[$1].centerOffset }

        guard let best = ranked.first else {
            return nil
        }

        guard ranked.count > 1 else {
            return best
        }

        let runnerUp = candidates[ranked[1]].centerOffset
        return runnerUp - candidates[best].centerOffset >= Self.centeringMargin ? best : nil
    }

    // MARK: - Usual place

    private func hasAnchor(at time: Double) -> Bool {
        guard anchorTorso != nil, let anchorTime else {
            return false
        }

        return time - anchorTime <= Self.relockTimeout
    }

    /// True when either size is unknown, the sizes differ by no more than landmark noise, or they
    /// are within `range` of each other.
    ///
    /// The absolute slack matters only for small shoulder widths: seen from the side (sit to
    /// stand), the two shoulders nearly overlap, so a few thousandths of jitter changed the ratio
    /// by half and dropped the patient. A nearer bystander differs by far more than the slack.
    private static func sizeMatches(_ size: Double, reference: Double, range: ClosedRange<Double>) -> Bool {
        guard size > 0, reference > 0 else {
            return true
        }

        guard abs(size - reference) > sizeNoise else {
            return true
        }

        return range.contains(size / reference)
    }

    /// True when there is no usual place yet, or the candidate's torso is the patient's size.
    /// Someone walking in front of the patient is nearer the camera, so their torso is larger.
    private func matchesAnchorSize(_ candidate: Candidate, range: ClosedRange<Double>, at time: Double) -> Bool {
        guard hasAnchor(at: time) else {
            return true
        }

        return Self.sizeMatches(candidate.size, reference: anchorSize, range: range)
    }

    /// True when there is no usual place yet, or the candidate sits within it.
    private func isNearAnchor(_ candidate: Candidate, at time: Double, gateScale: Double) -> Bool {
        guard let anchorTorso, hasAnchor(at: time) else {
            return true
        }

        let gate = max(0.1, anchorSize * 0.6) * gateScale
        return (candidate.torso - anchorTorso).length <= gate
    }

    /// Positions always follow the patient; sizes only from frames where both shoulders are seen,
    /// so a hidden shoulder never changes the reference the next frame is compared against.
    private mutating func remember(_ candidate: Candidate, at time: Double) {
        lastTorso = candidate.torso
        lastTime = time

        guard let anchorTorso, hasAnchor(at: time) else {
            // A new lock may be a different person, so no earlier size carries over.
            self.anchorTorso = candidate.torso
            anchorSize = candidate.size
            lastSize = candidate.size
            anchorTime = time
            return
        }

        if candidate.size > 0 {
            lastSize = candidate.size
        }

        let rate = Self.anchorFollowRate
        self.anchorTorso = anchorTorso + (candidate.torso - anchorTorso).scaled(rate)
        anchorTime = time

        guard candidate.size > 0 else {
            return
        }

        anchorSize = anchorSize > 0
            ? anchorSize + (candidate.size - anchorSize) * rate
            : candidate.size
    }
}
