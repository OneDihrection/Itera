//
//  TherapyActivity.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

struct TherapyViewport: Equatable {
    let width: Double
    let height: Double
}

struct TargetGuide {
    let start: TherapyPoint
    let target: TherapyPoint
    let tracked: TherapyPoint
    let radius: Double
    let targetActive: Bool
    var progress: Double
    let aspect: Double
    var directionTip: TherapyPoint? = nil
    var showsDirectionArrow = true
    var directionOnly = false
    var capturing = false
    var savedStart = false
    var farthest: TherapyPoint? = nil
}

enum ActivityStatus { case preparing, running, suspended, finished }
enum ExamplePose { case start, peak, looping }

enum ActivityCommand: Equatable {
    case redo
    case adjustTarget
    case retryStep
    case skipStep
}

enum MovementPhase { case startCapture, targetCapture, returnToStart, countdown, practice }
enum ReachPhase { case setup, assessment, countdown, rehearsal, practice, finished }

struct MovementSnapshot {
    var phase: MovementPhase = .startCapture
    var instruction = "session.holdStart"
    var progress = 0.0
    var count = 0
    var guide: TargetGuide?
    var pose: ExamplePose = .start
    var countingDown = false
    var seconds = 5
    var trackingMessage: String?
}

struct ReachSnapshot {
    var phase: ReachPhase = .setup
    var instruction = "session.reachStart"
    var progress = 0.0
    var count = 0
    var seconds = 0
    var guide: TargetGuide?
    var rehearsal = false
    var outcomes: [ReachOutcome] = []
    var practiceSeconds = 0.0
    var direction = 0
    var round = 0
    var step = 0
    var caregiverSkippedSteps: [ReachSkippedStep] = []
    var trackingMessage: String?
}

struct ReachSkippedStep: Codable, Equatable {
    enum Phase: String, Codable {
        case assessment
        case rehearsal
        case practice
    }

    let round: Int
    let direction: Int
    let phase: Phase
}

struct ReachOutcome: Codable, Equatable {
    enum Evidence: String, Codable { case reached, notReached, unscored }
    let direction: Int
    let evidence: Evidence
}

enum ActivityPresentation {
    case movement(MovementSnapshot)
    case reach(ReachSnapshot)
    case cup(CupSnapshot)
    case timed(TimedPracticeSnapshot)

    var countdownSeconds: Int? {
        switch self {
        case .movement(let value): return value.phase == .countdown ? value.seconds : nil
        case .reach(let value): return value.phase == .countdown ? value.seconds : nil
        case .cup(let value): return value.phase == .countdown ? value.seconds : nil
        case .timed: return nil
        }
    }

    var instruction: String {
        switch self {
        case .movement(let value): return value.instruction
        case .reach(let value): return value.instruction
        case .cup(let value): return value.instruction
        case .timed: return "session.timedPractice"
        }
    }
    var count: Int {
        switch self {
        case .movement(let value): return value.count
        case .reach(let value): return value.count
        case .cup(let value): return value.count
        case .timed: return 0
        }
    }
    var progress: Double {
        switch self {
        case .movement(let value): return value.progress
        case .reach(let value): return value.progress
        case .cup(let value): return value.progress
        case .timed(let value): return value.seconds / value.goal
        }
    }
    var guide: TargetGuide? {
        switch self {
        case .movement(let value): return value.guide
        case .reach(let value): return value.guide
        case .cup(let value): return value.guide
        case .timed: return nil
        }
    }
}

enum ActivityEvent {
    case observation(TrackingObservation)
    case tick(Double)
    case suspend
    case resume
    case recalibrate
    case viewport(TherapyViewport)
    case guidanceCompleted(Double)
    case command(ActivityCommand, at: Double)
}

struct ActivityTransition {
    let status: ActivityStatus
    let presentation: ActivityPresentation
}

protocol TherapyActivity {
    mutating func handle(_ event: ActivityEvent) -> ActivityTransition
    var presentation: ActivityPresentation { get }
}

/// Holds use a running mean rather than retaining a per-frame measurement stream.
struct StableHold {
    private var first: TherapyPoint?
    private var sum = TherapyPoint(x: 0, y: 0)
    private var count = 0
    private var since = 0.0
    private var last: Double?
    private(set) var progress = 0.0

    var mean: TherapyPoint? { count > 0 ? sum.scaled(1 / Double(count)) : nil }

    mutating func clear() { self = StableHold() }

    mutating func consume(_ point: TherapyPoint, time: Double, duration: Double, tolerance: Double, maximumGap: Double = 0.15)
    {
        if let last, time <= last || time - last > maximumGap {
            clear()
        }
        if let first, (point - first).length > tolerance {
            clear()
        }
        if first == nil {
            first = point
            since = time
        }
        sum = sum + point
        count += 1
        last = time
        progress = min(1, (time - since) / duration)
    }
}

func bubbleRadius(body: Double, separation: Double?, aspect: Double, viewport: TherapyViewport?)
    -> Double
{
    guard let viewport, viewport.width > 0, viewport.height > 0 else {
        return body
    }
    let height = min(viewport.height, viewport.width / aspect)
    var diameter = min(120, max(68, body * height * 2))
    if let separation { diameter = min(diameter, separation * height * 0.8) }
    return diameter / (height * 2)
}
