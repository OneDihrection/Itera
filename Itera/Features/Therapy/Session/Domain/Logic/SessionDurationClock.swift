//
//  SessionDurationClock.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 02/11/2026.
//

import Foundation

/// On-screen session duration includes guidance/rest/tracking waits, excluding explicit pauses.
/// It is separate from evidence-credited practice time in exercise results.
struct SessionDurationClock {
    private var accumulated = 0.0
    private var runningSince: Double?

    mutating func resume(at now: Double) {
        guard now.isFinite, runningSince == nil else {
            return
        }
        runningSince = now
    }

    mutating func pause(at now: Double) {
        guard now.isFinite, let runningSince else {
            return
        }
        accumulated += max(0, now - runningSince)
        self.runningSince = nil
    }

    func elapsed(at now: Double) -> Double {
        guard now.isFinite, let runningSince else {
            return accumulated
        }
        return accumulated + max(0, now - runningSince)
    }
}
