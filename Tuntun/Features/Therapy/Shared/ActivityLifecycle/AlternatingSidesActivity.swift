//
//  AlternatingSidesActivity.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation

/// A bilateral activity whose sides take turns after every credited repetition, as Balancing does.
///
/// Each side keeps its own single-side activity, so calibration, holds and counting stay where
/// they are. Before a set's countdown every side calibrates in turn; the countdown then starts on
/// the first side, and each credited repetition hands over to the other side on the next frame.
/// The set ends when the repetitions of both sides together reach the configuration's goal.
struct AlternatingSidesActivity: TherapyActivity {
    private struct Side {
        let side: TherapySide
        var activity: any TherapyActivity
        /// The side's own count when it was last read, so its new repetitions add to the total.
        var count = 0
        /// The side reached its countdown while the set was being started.
        var ready = false
    }

    private let goal: Int
    private var sides: [Side]
    private var active = 0
    private var total = 0
    /// True from the start of a set until its countdown ends; sides calibrate in turn meanwhile.
    private var startingSet = true
    /// A repetition was just credited: the other side takes over on the next frame, so the
    /// crediting frame still belongs to the side that moved.
    private var switchPending = false
    private var activeStatus = ActivityStatus.running

    /// - Parameters:
    ///   - configuration: The bilateral activity; `side` is the side that starts and `goal` counts
    ///     the repetitions of both sides together.
    ///   - makeActivity: Builds the single-side activity for one side's configuration; nil when
    ///     the exercise has none, which fails the initializer.
    init?(
        configuration: SessionActivity,
        makeActivity: (SessionActivity) -> (any TherapyActivity)?
    ) {
        goal = configuration.goal

        let order: [TherapySide] = configuration.side == .left
            ? [.left, .right]
            : [.right, .left]

        // Each side never finishes by itself; only the shared total ends the set.
        var sides: [Side] = []

        for side in order {
            let sideConfiguration = SessionActivity(
                kind: configuration.kind,
                side: side,
                goal: .max,
                sets: configuration.sets
            )

            guard let activity = makeActivity(sideConfiguration) else {
                return nil
            }

            sides.append(Side(side: side, activity: activity))
        }

        self.sides = sides

        // The towel waits in its countdown from the start, so its sides are ready at once.
        settleStartingSet()
    }

    /// The side currently exercising.
    var activeSide: TherapySide {
        sides[active].side
    }

    var presentation: ActivityPresentation {
        let current = sides[active].activity.presentation

        switch current {
        case .movement(var value):
            value.count = total
            value.practiceSeconds = practiceSeconds
            return .movement(value)
        case .towel(var value):
            value.count = total
            value.practiceSeconds = practiceSeconds
            return .towel(value)
        case .reach(var value):
            value.count = total
            value.round = total + 1
            value.outcomes = reachSnapshots.flatMap(\.outcomes)
            value.practiceSeconds = practiceSeconds
            value.caregiverSkippedSteps = reachSnapshots.flatMap(\.caregiverSkippedSteps)
            return .reach(value)
        case .timed:
            return current
        }
    }

    mutating func handle(_ event: ActivityEvent) -> ActivityTransition {
        let before = presentation
        let previousSide = activeSide

        switch event {
        case .observation:
            if switchPending {
                switchPending = false
                active = (active + 1) % sides.count
            }

            forwardToActive(event)
        case .preview, .tick, .guidanceCompleted, .command:
            // A pending switch waits for a scored frame, so the guide stays on the side just credited.
            forwardToActive(event)
        case .viewport, .suspend, .resume:
            forwardToAll(event)
        case .recalibrate, .nextSet:
            forwardToAll(event)
            beginSet(resettingTotal: isNextSet(event))
        case .countdownFinished:
            finishCountdowns(event)
        }

        creditRepetitions()
        settleStartingSet()

        let after = presentation
        var facts = ActivityFact.changes(from: before, to: after)

        if activeSide != previousSide {
            facts.append(.sideChanged(activeSide))
        }

        return ActivityTransition(
            status: status,
            presentation: after,
            facts: facts
        )
    }

    // MARK: - Routing

    private var status: ActivityStatus {
        if total >= goal {
            return .finished
        }

        // A side never finishes alone; the shared total decides.
        return activeStatus == .finished ? .running : activeStatus
    }

    private mutating func forwardToActive(_ event: ActivityEvent) {
        activeStatus = sides[active].activity.handle(event).status
    }

    private mutating func forwardToAll(_ event: ActivityEvent) {
        for index in sides.indices {
            let status = sides[index].activity.handle(event).status

            if index == active {
                activeStatus = status
            }
        }
    }

    /// Ends the countdown of every side waiting in one, so a side reached later starts practising.
    private mutating func finishCountdowns(_ event: ActivityEvent) {
        for index in sides.indices where sides[index].activity.presentation.countdownLength != nil {
            let status = sides[index].activity.handle(event).status

            if index == active {
                activeStatus = status
            }
        }

        startingSet = false
    }

    private func isNextSet(_ event: ActivityEvent) -> Bool {
        if case .nextSet = event {
            return true
        }

        return false
    }

    /// A new set or a fresh calibration starts again on the first side.
    private mutating func beginSet(resettingTotal: Bool) {
        if resettingTotal {
            total = 0
        }

        startingSet = true
        switchPending = false
        active = 0

        for index in sides.indices {
            sides[index].ready = false
            sides[index].count = sides[index].activity.presentation.count
        }
    }

    // MARK: - Turns

    /// Adds the active side's new repetitions to the total and hands over to the other side.
    private mutating func creditRepetitions() {
        let count = sides[active].activity.presentation.count
        let added = count - sides[active].count
        sides[active].count = count

        // A side that restarted its count (redo) adds nothing and takes nothing away.
        guard added > 0 else {
            return
        }

        total += added

        if !startingSet, total < goal {
            switchPending = true
        }
    }

    /// While a set is being started, a side that reached its countdown has finished calibrating:
    /// the next uncalibrated side takes over. Once every side is ready, the countdown is shown on
    /// the first side.
    private mutating func settleStartingSet() {
        guard startingSet else {
            return
        }

        while sides[active].activity.presentation.countdownLength != nil {
            sides[active].ready = true

            guard let next = sides.firstIndex(where: { !$0.ready }) else {
                active = 0
                return
            }

            active = next
        }
    }

    /// Both sides' practice time together, as the set's one result covers both.
    private var practiceSeconds: Double {
        sides.reduce(0) { $0 + $1.activity.presentation.practiceSeconds }
    }

    private var reachSnapshots: [ReachSnapshot] {
        sides.compactMap { side in
            if case .reach(let value) = side.activity.presentation {
                return value
            }

            return nil
        }
    }
}
