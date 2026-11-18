//
//  Countdown.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation

/// The pre-practice countdown. It shows its full length while its cue is spoken, starts when the
/// cue ends, and announces each whole second once. A suspension stops it; the guided session
/// restarts it from its full length after the cue is spoken again.
struct Countdown: Equatable {
    /// Seconds from start to finish: 3, or 5 before a later set of the arm-raise script.
    let length: Int
    /// When it finishes; nil while it waits for its cue.
    private(set) var endsAt: Double?
    private var announced: Int?

    init(length: Int) {
        self.length = length
    }

    var isRunning: Bool { endsAt != nil }

    func seconds(at now: Double) -> Int {
        guard let endsAt else {
            return length
        }

        return max(0, Int(ceil(endsAt - now)))
    }

    func isFinished(at now: Double) -> Bool {
        guard let endsAt else {
            return false
        }

        return now >= endsAt
    }

    mutating func start(at now: Double) {
        endsAt = now + Double(length)
        announced = nil
    }

    mutating func stop() {
        endsAt = nil
        announced = nil
    }

    /// The second to speak now, once per whole second while running; nil otherwise.
    mutating func takeAnnouncement(at now: Double) -> Int? {
        guard isRunning else {
            return nil
        }

        let seconds = seconds(at: now)

        guard seconds > 0, seconds != announced else {
            return nil
        }

        announced = seconds
        return seconds
    }
}
