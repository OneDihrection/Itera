//
//  FingerTrackingRecovery.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 03/11/2026.
//

import Foundation

enum FingerTrackingProblem: Equatable {
    case position, selectedHand, fingers, multipleHands, camera
}

/// Debounces recovery presentation only. Missing evidence never receives exercise credit.
struct FingerTrackingRecovery {
    private(set) var problem: FingerTrackingProblem?
    private var problemSince: Double?
    private var goodSince: Double?
    private var lastGood: Double?
    private var candidate: FingerTrackingProblem?
    private var candidateSince: Double?
    /// When per-frame misses began, before they were long enough to count as a problem.
    private var frameMissingSince: Double?

    /// Misses shorter than this are detector dropouts, not a tracking problem.
    static let frameTolerance = 0.3

    mutating func reset() {
        self = Self()
    }

    /// Records one frame without usable evidence, ignoring dropouts shorter than
    /// `frameTolerance`. A single bad frame used to start a problem, and recovering from it
    /// then required 0.35 s of good frames, so every dropout froze the hold for about 0.4 s.
    /// The missing frames themselves still earn no hold credit; the activity freezes the hold.
    mutating func missingFrame(_ problem: FingerTrackingProblem, at now: Double) {
        guard now.isFinite else {
            return
        }

        guard self.problem == nil else {
            missing(problem, at: now)
            return
        }

        let since = frameMissingSince ?? now
        frameMissingSince = since

        guard now - since >= Self.frameTolerance else {
            return
        }

        missing(problem, at: now)
        problemSince = since
        frameMissingSince = nil
    }

    mutating func missing(_ problem: FingerTrackingProblem, at now: Double) {
        guard now.isFinite else {
            return
        }
        if problemSince == nil {
            problemSince = now
        }
        if self.problem == nil {
            self.problem = problem
        } else if self.problem != problem {
            if candidate != problem {
                candidate = problem
                candidateSince = now
            } else if now - (candidateSince ?? now) >= 0.4 {
                self.problem = problem
                candidate = nil
                candidateSince = nil
            }
        } else {
            candidate = nil
            candidateSince = nil
        }
        goodSince = nil
        lastGood = nil
    }

    mutating func visible(at now: Double) -> Bool {
        guard now.isFinite else {
            return false
        }
        guard problem != nil else {
            frameMissingSince = nil
            return true
        }
        if goodSince == nil || now - (lastGood ?? now) > 0.3 || now <= (lastGood ?? -.infinity) {
            goodSince = now
        }
        lastGood = now
        guard now - (goodSince ?? now) >= 0.35 else {
            return false
        }
        reset()
        return true
    }

    func showsGuidance(at now: Double) -> Bool {
        guard let problemSince else {
            return false
        }
        return now - problemSince >= 1
    }

    func requiresPause(at now: Double, cameraStartup: Bool = false) -> Bool {
        guard let problemSince else {
            return false
        }
        let timeout = problem == .camera ? (cameraStartup ? 10.0 : 3.0) : 8.0
        return now - problemSince >= timeout
    }
}
