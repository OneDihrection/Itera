//
//  SitToStandBalanceEngine.swift
//  Tuntun
//
//  Created by Fauzan Azima on 09/11/2026.
//

import Foundation

/// Runs `SitToStandActivity` inside the Balancing screens.
///
/// The activity keeps all of its own sit-to-stand logic; this adapter feeds it tracking frames and
/// presents its progress in Balancing's vocabulary so both exercises share one layout and flow:
///
/// - holding a comfortable seat, and the patient's own trial repetition, are the two calibration steps;
/// - returning to the seat before practice is the return phase, followed by the three-second countdown;
/// - leaning and standing are the repetition itself, and each counted repetition is a "touch".
struct SitToStandBalanceEngine: BalanceMovementEngine {
    private(set) var snapshot = BalanceSnapshot()
    var viewport: TherapyViewport?

    /// The hip circle is smaller than the 100 pt target bubbles, so it reads as the tracked hip
    /// rather than a place to reach.
    private static let hipDiameter = 72.0

    /// The hip circle's radius in normalized image height for the current camera frame.
    private func hipRadius(aspect: Double) -> Double {
        fixedBubbleRadius(diameter: Self.hipDiameter, aspect: aspect, viewport: viewport)
    }
    private var activity: SitToStandActivity
    private let goal: Int
    private var suspended = false

    init(goal: Int) {
        self.goal = max(1, goal)
        activity = Self.makeActivity(goal: max(1, goal))
        snapshot.goal = self.goal
        snapshot.holdDuration = 0
        snapshot.instructionKey = "sitToStand.tracking"
    }

    private static func makeActivity(goal: Int) -> SitToStandActivity {
        SitToStandActivity(goal: goal)
    }

    mutating func consume(_ frame: TrackingObservation, scoringEnabled: Bool) {
        if !scoringEnabled {
            if !suspended {
                suspended = true
                activity.suspend()
            }

            return
        }

        if suspended {
            suspended = false
            activity.resume()
        }

        activity.observe(frame)
        activity.tick(frame.timestamp)
        present(activity.presentation)
    }

    mutating func invalidateCalibration() {
        activity.recalibrate()
        snapshot.phase = .findingBody
        snapshot.overlay = nil
        snapshot.calibrationProgress = 0
        snapshot.calibrationCountdown = nil
        snapshot.instructionKey = "sitToStand.tracking"
    }

    mutating func restart() {
        self = SitToStandBalanceEngine(goal: goal)
    }

    mutating func nextSet() {
        activity.startNextSet()
        snapshot.metrics = BalanceMetrics()
        snapshot.phase = .returning
        snapshot.calibrationCountdown = nil
        snapshot.instructionKey = "sts.sitDown"
    }

    // MARK: - Presentation

    private mutating func present(_ value: SitToStandSnapshot) {
        snapshot.metrics.completedTouches = value.count
        snapshot.hipAngle = value.hipAngle
        snapshot.trunkLean = value.trunkLean
        snapshot.instructionKey = value.trackingMessage ?? value.cue ?? value.instruction

        if value.count >= goal {
            snapshot.phase = .complete
            snapshot.calibrationCountdown = nil
            snapshot.instructionKey = "sitToStand.voice.complete"

            // Nothing is left to do, so no next move is shown.
            var finished = value
            finished.guide = nil
            snapshot.overlay = overlay(for: finished, marker: nil)
            return
        }

        switch value.phase {
        case .seatedCapture:
            snapshot.phase = value.joints == nil ? .findingBody : .calibrating
            snapshot.calibrationProgress = value.progress
            snapshot.calibrationCountdown = value.progress > 0 ? max(1, value.seconds) : nil
        case .trial:
            // Standing still at the top of the trial counts down like the seated hold.
            snapshot.phase = .calibratingRange
            snapshot.calibrationProgress = value.progress
            snapshot.calibrationCountdown = value.progress > 0 ? max(1, value.seconds) : nil
        case .returnToSeat:
            snapshot.phase = .returning
            snapshot.calibrationCountdown = nil
        case .countdown:
            snapshot.phase = .calibrating
            snapshot.calibrationProgress = 1 - value.progress
            snapshot.calibrationCountdown = max(1, value.seconds)
        case .practice:
            snapshot.calibrationCountdown = nil

            switch value.stage {
            case .seated: snapshot.phase = .reaching
            case .rising, .standing, .lowering: snapshot.phase = .holding
            }
        }

        // Blue marks the seated start, orange the standing end, as in the other exercises.
        let marker: Bool? = snapshot.calibrationCountdown == nil
            ? nil
            : (snapshot.phase == .calibratingRange ? false : true)
        snapshot.overlay = overlay(for: value, marker: marker)
    }

    /// The hip as one circle beside the patient: its arc is the hold during calibration and the
    /// progress through each repetition during practice, with an arrow for the next move.
    /// - Parameter marker: `nil` outside a calibration hold, `true` for the seated hold and
    ///   `false` for the standing one.
    private func overlay(for value: SitToStandSnapshot, marker: Bool?) -> BalanceOverlay? {
        guard let joints = value.joints else {
            return nil
        }

        return BalanceOverlay(
            aspect: value.aspect,
            midlineBase: joints.hip,
            midlineTop: joints.shoulder,
            leftShoulder: joints.shoulder,
            rightShoulder: joints.shoulder,
            leftHip: joints.hip,
            rightHip: joints.hip,
            wrist: joints.hip,
            target: joints.hip,
            isReturnTarget: marker ?? false,
            targetRadius: hipRadius(aspect: value.aspect),
            crossedMidline: false,
            targetProgress: hipProgress(for: value, marker: marker),
            holdSecondsRemaining: marker == nil ? nil : snapshot.calibrationCountdown,
            compensationWarning: value.cue != nil,
            isCalibrationHold: true,
            calibrationTip: value.guide?.tip,
            calibrationTail: value.guide?.tail,
            calibrationJoint: value.guide?.joint,
            holdActive: isHipActive(value),
            completions: value.completions
        )
    }

    /// Quiet while returning to the seat before practice and while the current repetition cannot
    /// count, so a filling arc always means progress that will be counted.
    private func isHipActive(_ value: SitToStandSnapshot) -> Bool {
        switch value.phase {
        case .returnToSeat:
            return false
        case .practice:
            return value.repetitionCounts
        case .seatedCapture, .trial, .countdown:
            return true
        }
    }

    /// The hip circle's arc: the calibration hold while one runs, the progress through the current
    /// repetition during practice, and empty otherwise.
    private func hipProgress(for value: SitToStandSnapshot, marker: Bool?) -> Double {
        if marker != nil {
            return snapshot.calibrationProgress
        }

        guard value.phase == .practice else {
            return 0
        }

        return min(1, max(0, value.repetitionProgress))
    }
}
