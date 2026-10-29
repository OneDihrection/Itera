//
//  SessionGuidance.swift
//  Itera
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

    static func opening(_ activity: SessionActivity, includePositioning: Bool) -> Self {
        if activity.kind == .cup {
            return Self(cards: [Card(key: "parity.cupOpening")], destination: .activity, quietDelay: 1)
        }
        if activity.kind == .directionalReach {
            return Self(cards: [Card(key: "parity.reachOpening")], destination: .activity, quietDelay: 1, watchdog: 12)
        }
        let positioning = includePositioning ? "positioning" : "ready"
        let key = "session.opening.\(activity.kind.rawValue).\(activity.side.rawValue).\(positioning)"
        return Self(
            cards: [
                Card(key: key),
                Card(key: "parity.example.\(activity.side.rawValue)", demonstration: true)
            ],
            destination: .capture
        )
    }
}
