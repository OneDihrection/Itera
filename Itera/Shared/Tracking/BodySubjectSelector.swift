//
//  BodySubjectSelector.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import Foundation

/// Chooses which detected person is the patient when others are in view.
///
/// The patient sits facing the iPad, so a bystander walking past is usually smaller and
/// briefly overlaps them at most. Selection prefers, in order:
/// 1. **Continuity**: the person whose torso is nearest the patient's recently tracked torso,
///    at a similar size.
/// 2. **Dominance**: a person clearly larger (closer to the camera) than everyone else.
///
/// When neither rule settles it, no subject is reported. Anatomical sides always come from
/// the selected person's own landmarks, never from screen position.
struct BodySubjectSelector {
    struct Candidate {
        /// Aspect-corrected mean of the confident torso joints.
        let torso: TherapyPoint
        /// Aspect-corrected diagonal of the confident joints' bounding box.
        let size: Double
    }

    /// How long a lost patient remains the preferred subject. Matches the exercise hold grace.
    static let continuityWindow = 1.5
    private static let dominanceRatio = 1.4
    private static let sizeRange = 0.6...1.6

    private var lastTorso: TherapyPoint?
    private var lastSize = 0.0
    private var lastTime: Double?
    private var generation: UUID?

    mutating func reset() {
        lastTorso = nil
        lastSize = 0
        lastTime = nil
        generation = nil
    }

    /// - Returns: the index of the patient in `candidates`, or `nil` when ambiguous.
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

        lastTorso = candidates[index].torso
        lastSize = candidates[index].size
        lastTime = time

        return index
    }

    // MARK: - Rules

    private func continuingIndex(in candidates: [Candidate], at time: Double) -> Int? {
        guard let lastTorso,
              let lastTime,
              time - lastTime <= Self.continuityWindow,
              lastSize > 0 else {
            return nil
        }

        // A seated patient's torso moves well under half a body-size between tracked frames.
        let gate = max(0.08, lastSize * 0.5)

        let nearest = candidates.indices
            .filter { Self.sizeRange.contains(candidates[$0].size / lastSize) }
            .map { (index: $0, distance: (candidates[$0].torso - lastTorso).length) }
            .min { $0.distance < $1.distance }

        guard let nearest, nearest.distance <= gate else {
            return nil
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
