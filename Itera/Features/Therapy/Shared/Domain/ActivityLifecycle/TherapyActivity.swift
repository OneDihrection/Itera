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
    var tracked: TherapyPoint
    let radius: Double
    let targetActive: Bool
    var progress: Double
    let aspect: Double
    var directionTip: TherapyPoint? = nil
    var showsDirectionArrow = true
    var directionOnly = false
    /// Draws the hold ring around the tracked joint instead of around a bubble.
    var jointHold = false
    var capturing = false
    var savedStart = false
    var farthest: TherapyPoint? = nil
    var acceptedInside: Bool? = nil
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
    var seconds = 3
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
    case towel(TowelSnapshot)
    case movement(MovementSnapshot)
    case reach(ReachSnapshot)
    case cup(CupSnapshot)
    case timed(TimedPracticeSnapshot)
    case sitToStand(SitToStandSnapshot)

    var countdownSeconds: Int? {
        switch self {
        case .towel(let value): return value.phase == .countdown ? value.seconds : nil
        case .movement(let value): return value.phase == .countdown ? value.seconds : nil
        case .reach(let value): return value.phase == .countdown ? value.seconds : nil
        case .cup(let value): return value.phase == .countdown ? value.seconds : nil
        case .timed(let value): return value.countdownSeconds
        case .sitToStand(let value): return value.phase == .countdown ? value.seconds : nil
        }
    }

    var instruction: String {
        switch self {
        case .towel(let value): return value.instruction
        case .movement(let value): return value.instruction
        case .reach(let value): return value.instruction
        case .cup(let value): return value.instruction
        case .timed: return "session.timedPractice"
        case .sitToStand(let value): return value.instruction
        }
    }
    var count: Int {
        switch self {
        case .towel(let value): return value.count
        case .movement(let value): return value.count
        case .reach(let value): return value.count
        case .cup(let value): return value.count
        case .timed: return 0
        case .sitToStand(let value): return value.count
        }
    }
    var progress: Double {
        switch self {
        case .towel(let value): return value.holdProgress
        case .movement(let value): return value.progress
        case .reach(let value): return value.progress
        case .cup(let value): return value.progress
        case .timed(let value): return value.seconds / value.goal
        case .sitToStand(let value): return value.progress
        }
    }
    var guide: TargetGuide? {
        switch self {
        case .towel: return nil
        case .movement(let value): return value.guide
        case .reach(let value): return value.guide
        case .cup(let value): return value.guide
        case .timed, .sitToStand: return nil
        }
    }
}

enum ActivityEvent {
    case observation(TrackingObservation)
    case tick(Double)
    case suspend
    case resume
    case recalibrate
    case nextSet
    case viewport(TherapyViewport)
    case countdownReady(Double)
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
///
/// Progress is credited time, not wall time: only intervals between consecutive accepted
/// samples of at most `creditedStep` count. With the defaults (`creditedStep` equal to
/// `maximumGap`, no wobble grace) this matches clearing the hold on any gap, as before.
/// Callers that pass a longer `maximumGap` let a hold survive brief tracking loss while
/// the missing interval still earns nothing.
struct StableHold {
    private var first: TherapyPoint?
    private var sum = TherapyPoint(x: 0, y: 0)
    private var count = 0
    private var elapsed = 0.0
    private var last: Double?
    private var outsideSince: Double?
    private(set) var progress = 0.0

    var mean: TherapyPoint? { count > 0 ? sum.scaled(1 / Double(count)) : nil }

    /// True once a hold has started and has not been cleared.
    var isActive: Bool { first != nil }

    mutating func clear() { self = StableHold() }

    /// - Parameters:
    ///   - maximumGap: the longest gap between samples that keeps the hold alive.
    ///   - creditedStep: the longest gap that earns hold time; defaults to `maximumGap`.
    ///   - wobbleGrace: how long samples may stray beyond `tolerance` before the hold
    ///     restarts. Strayed samples are ignored and earn nothing.
    mutating func consume(
        _ point: TherapyPoint,
        time: Double,
        duration: Double,
        tolerance: Double,
        maximumGap: Double = 0.15,
        creditedStep: Double? = nil,
        wobbleGrace: Double = 0
    ) {
        if let last, time <= last || time - last > maximumGap {
            clear()
        }

        if let first, (point - first).length > tolerance {
            let since = outsideSince ?? time

            if time - since < wobbleGrace {
                // A brief stray sample is ignored; the interval up to it is not credited.
                outsideSince = since
                last = time
                return
            }

            // Sustained drift: this sample starts a new hold below.
            clear()
        }

        outsideSince = nil

        if first == nil {
            first = point
        } else if let last, time - last <= (creditedStep ?? maximumGap) {
            elapsed += time - last
        }

        sum = sum + point
        count += 1
        last = time
        progress = min(1, elapsed / duration)
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
