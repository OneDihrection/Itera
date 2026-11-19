//
//  ShaderMotionClock.swift
//  Tuntun
//
//  Created by dimaswisodewo on 19/11/2026.
//

import Foundation

/// Seconds of shader idle motion, excluding time spent paused, so resuming never jumps.
/// Shared by the breathing shaders, which drive it from their `TimelineView`.
struct ShaderMotionClock {
    private var accumulated = 0.0
    private var runningSince: Date?

    mutating func resume(at date: Date) {
        guard runningSince == nil else {
            return
        }

        runningSince = date
    }

    mutating func pause(at date: Date) {
        guard let runningSince else {
            return
        }

        accumulated += max(0, date.timeIntervalSince(runningSince))
        self.runningSince = nil
    }

    func time(at date: Date) -> Double {
        guard let runningSince else {
            return accumulated
        }

        return accumulated + max(0, date.timeIntervalSince(runningSince))
    }
}
