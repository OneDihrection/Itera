//
//  HandSubjectSelector.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import Foundation

/// Chooses which detected hand belongs to the patient when more than one is visible.
///
/// Selection never uses screen position alone. It prefers, in order:
/// 1. **Continuity**: the hand nearest the patient's recently tracked hand, at a similar size.
/// 2. **Requested side**: the only hand whose reported chirality matches the exercised side.
/// 3. **Dominance**: a hand clearly larger (closer to the camera) than every other hand.
///
/// When none of these settles the choice, it reports no subject rather than guessing, so a
/// bystander's hand is never scored as the patient's.
struct HandSubjectSelector {
    struct Candidate {
        /// Aspect-corrected wrist position in unmirrored image coordinates.
        let wrist: TherapyPoint
        /// Aspect-corrected wrist-to-middle-knuckle length; a proxy for distance to the camera.
        let size: Double
        let side: HandSide?
    }

    /// How long a lost hand remains the preferred subject. Matches the exercise hold grace.
    static let continuityWindow = 1.5
    /// A candidate this much larger than every other hand is treated as the patient's.
    private static let dominanceRatio = 1.4
    /// Accepted size change between the tracked hand and a continuity candidate.
    private static let sizeRange = 0.6...1.6

    var preferredSide: HandSide?
    private var lastWrist: TherapyPoint?
    private var lastSize = 0.0
    private var lastTime: Double?
    private var generation: UUID?

    /// Forgets the tracked hand; the requested side is kept.
    mutating func reset() {
        lastWrist = nil
        lastSize = 0
        lastTime = nil
        generation = nil
    }

    /// - Returns: the index of the patient's hand in `candidates`, or `nil` when ambiguous.
    mutating func select(_ candidates: [Candidate], at time: Double, generation: UUID) -> Int? {
        if self.generation != generation {
            reset()
            self.generation = generation
        }

        guard !candidates.isEmpty else {
            return nil
        }

        guard let index = continuingIndex(in: candidates, at: time) ?? initialIndex(in: candidates) else {
            return nil
        }

        let selected = candidates[index]
        lastWrist = selected.wrist
        lastSize = selected.size
        lastTime = time

        return index
    }

    // MARK: - Rules

    private func continuingIndex(in candidates: [Candidate], at time: Double) -> Int? {
        guard let lastWrist,
              let lastTime,
              time - lastTime <= Self.continuityWindow,
              lastSize > 0 else {
            return nil
        }

        // A hand moves at most a few hand-lengths between tracked frames.
        let gate = max(0.12, lastSize * 3)

        let nearest = candidates.indices
            .filter { Self.sizeRange.contains(candidates[$0].size / lastSize) }
            .map { (index: $0, distance: (candidates[$0].wrist - lastWrist).length) }
            .min { $0.distance < $1.distance }

        guard let nearest, nearest.distance <= gate else {
            return nil
        }

        return nearest.index
    }

    private func initialIndex(in candidates: [Candidate]) -> Int? {
        if candidates.count == 1 {
            return 0
        }

        if let preferredSide {
            let matching = candidates.indices.filter { candidates[$0].side == preferredSide }

            if matching.count == 1 {
                return matching[0]
            }
        }

        return dominantSubjectIndex(sizes: candidates.map(\.size), ratio: Self.dominanceRatio)
    }
}

/// The index of a detected subject at least `ratio` times larger than every other one.
///
/// Shared by the hand and body selectors: a clearly larger subject is the one closest to
/// the camera, which is where the patient sits.
func dominantSubjectIndex(sizes: [Double], ratio: Double) -> Int? {
    let ranked = sizes.indices.sorted { sizes[$0] > sizes[$1] }

    guard ranked.count >= 2 else {
        return ranked.first
    }

    let largest = sizes[ranked[0]]
    let runnerUp = sizes[ranked[1]]

    guard largest > 0, largest >= runnerUp * ratio else {
        return nil
    }

    return ranked[0]
}
