//
//  Suspension.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation

/// Why a guided session is not progressing, and what stops it from resuming.
///
/// Reasons freeze the session: `pause` is cleared only by an explicit Resume (touch or "go"),
/// and covers backgrounding and audio interruptions too; `cameraWait` clears itself when fresh
/// frames return. Blockers never freeze anything on their own; they only refuse Resume until
/// the view model reports them cleared.
///
/// The frozen interval starts with the first reason and stays open until `end()`, so the engine
/// decides when time starts counting again and shifts every deadline by the same amount.
struct Suspension: Equatable {
    enum Reason: Hashable {
        case pause
        case cameraWait
    }

    enum Blocker: Hashable {
        case voiceUnavailable
        case storageFailure
    }

    private(set) var reasons: Set<Reason> = []
    private(set) var blockers: Set<Blocker> = []
    /// When the open frozen interval began; nil when no interval is open.
    private(set) var since: Double?

    var isPaused: Bool { reasons.contains(.pause) }
    var isWaitingForCamera: Bool { reasons.contains(.cameraWait) }
    var canResume: Bool { blockers.isEmpty }

    /// Adds a reason and opens the frozen interval if none is open. Returns false when the
    /// reason was already present.
    mutating func insert(_ reason: Reason, at time: Double) -> Bool {
        guard reasons.insert(reason).inserted else {
            return false
        }

        if since == nil {
            since = time
        }

        return true
    }

    /// Removes a reason. Returns false when it was not present. The frozen interval stays open
    /// until `end()`.
    mutating func remove(_ reason: Reason) -> Bool {
        reasons.remove(reason) != nil
    }

    /// Closes the frozen interval and returns when it began, or nil when none was open.
    mutating func end() -> Double? {
        defer {
            since = nil
        }

        return since
    }

    /// Sets or clears a blocker. Returns true only when an inactive blocker became active.
    mutating func setBlocker(_ blocker: Blocker, _ active: Bool) -> Bool {
        guard active else {
            blockers.remove(blocker)
            return false
        }

        return blockers.insert(blocker).inserted
    }
}
