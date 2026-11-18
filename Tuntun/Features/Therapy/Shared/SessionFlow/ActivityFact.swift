//
//  ActivityFact.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation

/// Something an activity's last event changed, reported with its transition so the session
/// engine reacts to what happened instead of comparing presentations itself.
enum ActivityFact: Equatable {
    /// The activity entered its pre-practice countdown, which the session runs after its cue.
    case countdownRequested(seconds: Int)
    /// A movement activity moved between calibration and practice phases.
    case movementPhaseChanged(from: MovementPhase, to: MovementPhase)
    case repetitionCredited(Int)
    /// A movement repetition's target was reached; the return to start is next.
    case targetReached
    case towelFolded
    case towelGrabbed
    /// The activity's cue changed to this instruction key.
    case cueChanged(String)
    /// A bilateral activity handed over to this side (`AlternatingSidesActivity`).
    case sideChanged(TherapySide)

    /// The facts between an activity's presentation before and after one event. Activities call
    /// this once per event; it compares a few fields and allocates nothing when nothing changed.
    static func changes(from before: ActivityPresentation, to after: ActivityPresentation) -> [ActivityFact] {
        var facts: [ActivityFact] = []

        if let seconds = after.countdownLength, before.countdownLength == nil {
            facts.append(.countdownRequested(seconds: seconds))
        }

        switch (before, after) {
        case (.movement(let old), .movement(let new)):
            if old.phase != new.phase {
                facts.append(.movementPhaseChanged(from: old.phase, to: new.phase))
            }
            if let oldGuide = old.guide, let newGuide = new.guide, oldGuide.targetActive, !newGuide.targetActive {
                facts.append(.targetReached)
            }
        case (.towel(let old), .towel(let new)):
            if old.foldIndex != new.foldIndex {
                facts.append(.towelFolded)
            }
            if old.grabID != new.grabID {
                facts.append(.towelGrabbed)
            }
        default:
            break
        }

        if before.count != after.count {
            facts.append(.repetitionCredited(after.count))
        }

        if before.instruction != after.instruction {
            facts.append(.cueChanged(after.instruction))
        }

        return facts
    }
}

extension Array where Element == ActivityFact {
    var requestsCountdown: Bool {
        contains { fact in
            if case .countdownRequested = fact {
                return true
            }
            return false
        }
    }

    var creditsRepetition: Bool {
        contains { fact in
            if case .repetitionCredited = fact {
                return true
            }
            return false
        }
    }

    /// The side a bilateral activity handed over to, if it changed.
    var changedSide: TherapySide? {
        for fact in self {
            if case .sideChanged(let side) = fact {
                return side
            }
        }
        return nil
    }

    func entered(_ phase: MovementPhase, from previous: MovementPhase? = nil) -> Bool {
        contains { fact in
            guard case .movementPhaseChanged(let from, let to) = fact, to == phase else {
                return false
            }
            return previous.map { $0 == from } ?? true
        }
    }
}
