//
//  SessionGuidance.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

/// One opening instruction card, followed by a movement demonstration when available.
struct SessionGuidance {
    struct Card {
        let key: String
        var demonstration = false
    }

    enum Destination {
        case capture
        case returnToStart
        case activity
    }

    let cards: [Card]
    let destination: Destination
    var quietDelay: Double = 3
    var watchdog: Double = 20

    /// - Parameter side: The side being calibrated, when an alternating activity introduces each
    ///   side in turn; the activity's own side otherwise.
    static func opening(_ activity: SessionActivity, side: TherapySide? = nil, includePositioning: Bool) -> Self {
        let side = side ?? activity.side

        if activity.kind == .foldTowel {
            return Self(cards: [
                Card(key: "towel.opening." + side.rawValue),
                Card(key: "towel.demo", demonstration: true)
            ], destination: .activity)
        }
        if activity.kind == .directionalReach {
            // The reach card names no arm, so an alternating reach names it first.
            var cards = [Card(key: "parity.reachOpening")]
            if activity.alternatesSides {
                cards.insert(Card(key: "session.switchArm." + side.rawValue), at: 0)
            }
            return Self(cards: cards, destination: .capture, quietDelay: 1, watchdog: 12)
        }
        let positioning = includePositioning ? "positioning" : "ready"
        let key = "session.opening.\(activity.kind.rawValue).\(side.rawValue).\(positioning)"
        return Self(
            cards: [
                Card(key: key),
                Card(key: "parity.example.\(side.rawValue)", demonstration: true)
            ],
            destination: .capture
        )
    }
}
