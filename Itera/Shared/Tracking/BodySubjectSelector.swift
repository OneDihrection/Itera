//
//  BodySubjectSelector.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import Foundation

/// Chooses which detected person is the patient when others are in view, and keeps following them.
///
/// The first selection prefers a person clearly larger (closer to the camera) than everyone else.
/// From then on the selector is **locked** to that person: a candidate is accepted only if its
/// torso is near the patient's last torso and of a similar torso size, and a bystander is never
/// adopted just because they look larger. While the patient is out of view nothing is reported
/// (rather than switching people); only after `relockTimeout` without the patient may the
/// dominance rule pick again. Torso size, unlike the whole-body extent, does not change when the
/// patient raises or extends an arm.
///
/// Anatomical sides always come from the selected person's own landmarks, never from screen
/// position.
struct BodySubjectSelector {
    struct Candidate {
        /// Aspect-corrected mean of the confident torso joints.
        let torso: TherapyPoint
        /// Aspect-corrected diagonal of the confident joints' bounding box (for dominance).
        let size: Double
        /// Aspect-corrected diagonal of the confident torso joints' bounding box (for identity).
        let torsoSize: Double
    }

    /// How long a lost patient remains the preferred subject. Matches the exercise hold grace.
    static let continuityWindow = 1.5
    /// How long a locked patient may be missing before another person may be adopted.
    static let relockTimeout = 5.0
    private static let dominanceRatio = 1.4
    private static let torsoSizeRange = 0.75...1.33
    /// The second-nearest person must be this much farther than the nearest to count as unambiguous.
    private static let ambiguityMargin = 1.3

    private var lastTorso: TherapyPoint?
    private var lastTorsoSize = 0.0
    private var lastTime: Double?
    private var generation: UUID?

    /// Increments whenever a patient is newly locked, so smoothing never blends two people.
    private(set) var epoch = 0

    mutating func reset() {
        lastTorso = nil
        lastTorsoSize = 0
        lastTime = nil
        generation = nil
    }

    /// - Returns: the index of the patient in `candidates`, or `nil` when ambiguous or absent.
    mutating func select(_ candidates: [Candidate], at time: Double, generation: UUID) -> Int? {
        if self.generation != generation {
            reset()
            self.generation = generation
        }

        if let lastTime, time - lastTime > Self.relockTimeout {
            reset()
            self.generation = generation
        }

        guard !candidates.isEmpty else {
            return nil
        }

        if lastTorso != nil {
            return followLockedPatient(in: candidates, at: time)
        }

        guard let index = initialIndex(in: candidates),
              candidates[index].torsoSize > 0 else {
            return nil
        }

        lock(to: candidates[index], at: time)

        return index
    }

    // MARK: - Rules

    private mutating func lock(to candidate: Candidate, at time: Double) {
        lastTorso = candidate.torso
        lastTorsoSize = candidate.torsoSize
        lastTime = time
        epoch += 1
    }

    private mutating func followLockedPatient(in candidates: [Candidate], at time: Double) -> Int? {
        guard let lastTorso, let lastTime, lastTorsoSize > 0 else {
            return nil
        }

        // The gate grows with the time the patient was unseen, since they may have shifted.
        let elapsed = max(0, time - lastTime)
        let gate = max(0.05, lastTorsoSize * min(1.0, 0.25 + 0.15 * elapsed))

        let matches = candidates.indices
            .filter { candidates[$0].torsoSize > 0 }
            .filter { Self.torsoSizeRange.contains(candidates[$0].torsoSize / lastTorsoSize) }
            .map { (index: $0, distance: (candidates[$0].torso - lastTorso).length) }
            .sorted { $0.distance < $1.distance }

        guard let nearest = matches.first, nearest.distance <= gate else {
            return nil
        }

        let ambiguous = matches.count > 1
            && matches[1].distance <= gate
            && matches[1].distance < nearest.distance * Self.ambiguityMargin

        self.lastTime = time

        // When someone else is almost as close, keep following the old reference instead of
        // letting it drift toward the bystander.
        if !ambiguous {
            self.lastTorso = candidates[nearest.index].torso
            lastTorsoSize = lastTorsoSize * 0.9 + candidates[nearest.index].torsoSize * 0.1
        }

        return nearest.index
    }

    private func initialIndex(in candidates: [Candidate]) -> Int? {
        dominantSubjectIndex(
            sizes: candidates.map(\.size),
            ratio: Self.dominanceRatio
        )
    }
}
