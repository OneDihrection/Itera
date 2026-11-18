//
//  TimedPracticeActivity.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

/// An explicit caregiver alternative credits usable practice time, never repetitions.
struct TimedPracticeActivity: TherapyActivity {
    private let configuration: SessionActivity
    private let duration: Double
    private var elapsed = 0.0
    private var last: Double?
    private var suspended = false
    private var countingDown = false
    private var seconds = 3

    init(configuration: SessionActivity, duration: Double) {
        self.configuration = configuration
        self.duration = duration
    }

    var presentation: ActivityPresentation {
        .timed(
            TimedPracticeSnapshot(
                seconds: elapsed,
                goal: duration,
                countdownSeconds: countingDown ? seconds : nil
            )
        )
    }

    mutating func handle(_ event: ActivityEvent) -> ActivityTransition {
        let before = presentation
        switch event {
        case .nextSet:
            elapsed = 0
            last = nil
            countingDown = true
            seconds = 3
        case .countdownFinished:
            if countingDown {
                countingDown = false
                seconds = 0
                last = nil
            }
        case .suspend:
            suspended = true
            last = nil
        case .resume:
            suspended = false
            last = nil
        case .recalibrate: last = nil
        case .command(let command, _):
            if command == .redo {
                elapsed = 0
                last = nil
            }
        case .observation(let frame):
            guard !suspended else { break }
            // The session's countdown is running or waiting for its cue.
            guard !countingDown else { break }
            let left = configuration.side == .left
            let joints: [BodyJoint] = configuration.kind == .armRaise
                ? [left ? .leftHip : .rightHip, left ? .leftShoulder : .rightShoulder, left ? .leftElbow : .rightElbow]
                : [left ? .leftShoulder : .rightShoulder, left ? .leftElbow : .rightElbow, left ? .leftWrist : .rightWrist]
            guard joints.allSatisfy({ frame.point($0) != nil }) else {
                last = nil
                break
            }
            if let last, frame.timestamp > last, frame.timestamp - last <= 0.3 {
                elapsed = min(duration, elapsed + min(0.2, frame.timestamp - last))
            }
            last = frame.timestamp
        case .tick, .viewport, .guidanceCompleted: break
        }
        return ActivityTransition(
            status: elapsed >= duration ? .finished : (suspended ? .suspended : .running),
            presentation: presentation,
            facts: ActivityFact.changes(from: before, to: presentation)
        )
    }
}

struct TimedPracticeSnapshot {
    let seconds: Double
    let goal: Double
    var countdownSeconds: Int? = nil
}
