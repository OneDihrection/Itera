//
//  HandSubjectSelector.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import Foundation

/// Chooses which detected hand belongs to the patient when more than one is visible.
///
/// Selection never uses screen position alone. The first hand seen is the **most dominant**
/// one (the largest, so closest to the camera, preferring the exercised side), and the
/// selector then **locks onto it**:
/// 1. **Continuity**: while locked, only the hand nearest the locked hand, at a similar size,
///    can be selected. A bystander never takes over, even if the locked hand is briefly lost;
///    the selector reports no subject until the same hand returns or the lock expires.
/// 2. **Acquisition**: with no lock, the largest hand on the requested side wins, else the
///    largest hand overall.
struct HandSubjectSelector {
    struct Candidate {
        /// Aspect-corrected wrist position in unmirrored image coordinates.
        let wrist: TherapyPoint
        /// Aspect-corrected wrist-to-middle-knuckle length; a proxy for distance to the camera.
        let size: Double
        let side: HandSide?
    }

    /// How long a lost hand stays locked. Long enough to survive a brief occlusion or a
    /// fast turn without handing the exercise to someone else in the frame.
    static let continuityWindow = 6.0
    /// Accepted size change between the tracked hand and a continuity candidate.
    private static let sizeRange = 0.5...2.0

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

    /// - Returns: the index of the patient's hand in `candidates`, or `nil` when no hand is visible or the locked hand is out of sight.
    mutating func select(_ candidates: [Candidate], at time: Double, generation: UUID) -> Int? {
        if self.generation != generation {
            reset()
            self.generation = generation
        }

        guard !candidates.isEmpty else {
            return nil
        }

        let index: Int

        if isLocked(at: time) {
            // Locked: only the same hand qualifies; never fall back to another one.
            guard let continuing = continuingIndex(in: candidates) else {
                return nil
            }

            index = continuing
        } else {
            index = initialIndex(in: candidates)
        }

        let selected = candidates[index]
        lastWrist = selected.wrist
        lastSize = selected.size
        lastTime = time

        return index
    }

    // MARK: - Rules

    private func isLocked(at time: Double) -> Bool {
        guard lastWrist != nil, let lastTime, lastSize > 0 else {
            return false
        }

        return time - lastTime <= Self.continuityWindow
    }

    private func continuingIndex(in candidates: [Candidate]) -> Int? {
        guard let lastWrist else {
            return nil
        }

        // A hand moves at most a few hand-lengths between tracked frames, and further
        // the longer it has been out of sight.
        let gate = max(0.2, lastSize * 4)

        let nearest = candidates.indices
            .filter { Self.sizeRange.contains(candidates[$0].size / lastSize) }
            .map { (index: $0, distance: (candidates[$0].wrist - lastWrist).length) }
            .min { $0.distance < $1.distance }

        guard let nearest, nearest.distance <= gate else {
            return nil
        }

        return nearest.index
    }

    /// The most dominant hand: the largest on the requested side, else the largest overall.
    private func initialIndex(in candidates: [Candidate]) -> Int {
        let all = Array(candidates.indices)

        if let preferredSide {
            let matching = all.filter { candidates[$0].side == preferredSide }

            if let largest = matching.max(by: { candidates[$0].size < candidates[$1].size }) {
                return largest
            }
        }

        return all.max { candidates[$0].size < candidates[$1].size } ?? 0
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
