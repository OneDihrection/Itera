//
//  SessionStage.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation

/// Where the guided session is, with the data only that stage uses. Leaving a stage drops its
/// deadlines and flags, so nothing stale can carry into the next one.
///
/// `SessionEngine` alone changes it. Views read `presentation` through `SessionSnapshot.stage`.
enum SessionStage: Equatable {
    /// Waiting for the camera before the current activity's opening.
    case preparing
    /// Opening narration and cards, and the calibration cues around them.
    case opening(Opening)
    /// The activity is running: calibration holds, countdown and repetitions.
    case practice(Practice)
    /// The set has a recorded outcome and its feedback cue is playing.
    case feedback(Feedback)
    case rest(Rest)
    case summary

    struct Opening: Equatable {
        enum Step: Equatable {
            /// The generic calibration introduction, before the cards.
            case calibrationIntro
            /// The Indonesian arm-raise script's positioning line, then its start line.
            case scriptedPosition
            /// The revised left script waits here for the body before its calibration starts.
            case scriptedBodyCheck
            case scriptedStart
            case card(index: Int, demonstration: Bool)
            /// "Try the movement" before a target is captured; practice follows its deadline.
            case tryMovement
        }

        var step: Step
        /// When a card's quiet delay or the preparation ends; nil until its narration completes.
        var advanceAt: Double?
    }

    struct Practice: Equatable {
        /// The pre-practice countdown the activity is waiting through, if any.
        var countdown: Countdown?
    }

    struct Feedback: Equatable {
        let enteredAt: Double
        /// At least 2 s after entry and after the feedback cue; nil until the cue completes.
        var advanceAt: Double?
        /// The camera changed after the set ended, so the next set starts with calibration.
        var recalibrateBeforeNext = false
    }

    struct Rest: Equatable {
        /// The timed rest's end. Nil for a scripted rest, which ends when its breathing does.
        var deadline: Double?
        var breathing: BreathingRest?
        var recalibrateBeforeNext = false
    }

    var presentation: SessionSnapshot.Stage {
        switch self {
        case .preparing:
            return .preparing
        case .opening(let opening):
            guard case .card(_, let demonstration) = opening.step else {
                return .preparationWait
            }
            return demonstration ? .demonstration : .instruction
        case .practice:
            return .activity
        case .feedback:
            return .feedback
        case .rest:
            return .rest
        case .summary:
            return .summary
        }
    }

    /// True while the current set has no outcome yet, so skip, stop and recalibration apply to it.
    var isRecordable: Bool {
        switch self {
        case .preparing, .opening, .practice:
            return true
        case .feedback, .rest, .summary:
            return false
        }
    }

    /// The opening or feedback deadline. Other stages have none and ignore a new value.
    var advanceAt: Double? {
        get {
            switch self {
            case .opening(let opening): return opening.advanceAt
            case .feedback(let feedback): return feedback.advanceAt
            case .preparing, .practice, .rest, .summary: return nil
            }
        }
        set {
            switch self {
            case .opening(var opening):
                opening.advanceAt = newValue
                self = .opening(opening)
            case .feedback(var feedback):
                feedback.advanceAt = newValue
                self = .feedback(feedback)
            case .preparing, .practice, .rest, .summary:
                break
            }
        }
    }

    /// The scripted rest's breathing, if this is one.
    var breathing: BreathingRest? {
        get {
            guard case .rest(let rest) = self else {
                return nil
            }
            return rest.breathing
        }
        set {
            guard case .rest(var rest) = self else {
                return
            }
            rest.breathing = newValue
            self = .rest(rest)
        }
    }

    /// Moves every deadline of this stage later by a suspension, so no stage loses time to it.
    mutating func rebase(suspendedAt since: Double, resumedAt now: Double) {
        if let advanceAt {
            self.advanceAt = advanceAt + now - since
        }
        guard case .rest(var rest) = self, let deadline = rest.deadline, now >= since else {
            return
        }
        rest.deadline = deadline + now - since
        self = .rest(rest)
    }

    /// Remembers a camera change after the set ended, so the next set recalibrates first.
    mutating func requireRecalibrationBeforeNextSet() {
        switch self {
        case .feedback(var feedback):
            feedback.recalibrateBeforeNext = true
            self = .feedback(feedback)
        case .rest(var rest):
            rest.recalibrateBeforeNext = true
            self = .rest(rest)
        case .preparing, .opening, .practice, .summary:
            break
        }
    }
}
