//
//  SessionEngine.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum SessionEvent {
    case observation(TrackingObservation)
    case tick(Double)
    case command(SessionCommand)
    case availability(TrackingAvailability)
    case previewReady(Bool)
    case guidanceCompleted(UUID, Bool = true)
    case readingChanged(UUID, Bool)
    case viewport(TherapyViewport)
}

enum SessionEffect {
    case speak(UUID, String)
    case cancelSpeech
    case audio(UUID, SessionAudioCue)
    case checkpoint(SessionCheckpoint)
    case finalize(SessionSummary)
}

struct SessionSnapshot {
    enum Stage { case preparing, preparationWait, instruction, demonstration, activity, feedback, rest, summary }
    var guidanceID: UUID?
    var stage: Stage = .preparing
    var instruction = "session.cameraWait"
    var presentation: ActivityPresentation?
    var activity: SessionActivity?
    var activityCount = 0
    var index = 0
    var seconds = 0
    var paused = false
    var assistanceKey: String?
    var cameraWaiting = true
    var summary: SessionSummary?
}

struct SessionTransition {
    let snapshot: SessionSnapshot
    let effects: [SessionEffect]
}

/// One serialized owner of ordering, asynchronous identities, and terminal bookkeeping.
struct SessionEngine {
    private var progress: SessionProgress
    private var activity: (any TherapyActivity)?
    private(set) var snapshot = SessionSnapshot()
    private var effects: [SessionEffect] = []
    private var now = 0.0
    private var lastTimestamp: Double?
    private var generation: UUID?
    private var aspect: Double?
    private var previewReady = false
    private var captureReady = false
    private var guidance: UUID?
    private var narrationComplete = false
    private var readingComplete = false
    private var deadline: Double?
    private var speechTimeout: Double?
    private var waitingSince: Double?
    private var suspensionSince: Double?
    private var pausedSince: Double?
    private var viewport: TherapyViewport?
    private var began = false
    private var evidenceBoundary = 0.0
    private var guidancePlan: SessionGuidance?
    private var cardIndex = 0
    private var positioningPending = true
    private var feedbackEnteredAt = 0.0
    private var pendingPrefix: SessionAudioCue?
    private var guidanceStartedAt = 0.0

    init(routine: Routine = .demo(), date: Date = Date()) {
        progress = SessionProgress(routine: routine, startedAt: date)
        selectActivity()
    }

    mutating func handle(_ event: SessionEvent, at time: Double) -> SessionTransition {
        effects = []
        guard time.isFinite else {
            return transition
        }
        now = max(now, time)
        if !began {
            began = true
            effects.append(.checkpoint(checkpoint))
        }
        if snapshot.stage == .summary {
            return transition
        }
        switch event {
        case .command(let command): commandReceived(command)
        case .viewport(let value):
            viewport = value
            _ = activity?.handle(.viewport(value))
        case .previewReady(let ready): previewReady = ready
        case .availability(let availability):
            switch availability {
            case .ready(let generation):
                captureReady = true
                self.generation = generation
                lastTimestamp = nil
            case .waiting: captureReady = false
            case .discontinuity:
                captureReady = false
                generation = nil
                lastTimestamp = nil
                recalibrate()
                pause()
            }
        case .observation(let frame): observation(frame)
        case .guidanceCompleted(let id, let available): completeGuidance(id, available: available)
        case .readingChanged(let id, let complete):
            guard canProgress, snapshot.guidanceID == id else {
                return transition
            }
            readingComplete = complete
            scheduleGuidanceAdvance()
        case .tick:
            updateReadiness()
            tick()
        }
        snapshot.guidanceID = guidance
        snapshot.activity = progress.currentActivity
        snapshot.index = progress.index
        snapshot.activityCount = progress.routine.activities.count
        snapshot.paused = pausedSince != nil
        snapshot.summary = progress.summary
        if let summary = progress.summary, snapshot.stage != .summary {
            snapshot.stage = .summary
            effects.append(.cancelSpeech)
            effects.append(.finalize(summary))
            effects.append(.audio(UUID(), .closing(completed: !summary.stopped && summary.results.allSatisfy { $0.outcome == .completed })))
        }
        return transition
    }

    private var transition: SessionTransition {
        SessionTransition(snapshot: snapshot, effects: effects)
    }
    private var checkpoint: SessionCheckpoint {
        SessionCheckpoint(
            id: progress.id, routine: progress.routine, startedAt: progress.startedAt,
            results: progress.results)
    }
    private var canProgress: Bool { pausedSince == nil && !snapshot.cameraWaiting }

    private mutating func selectActivity() {
        guard let configuration = progress.currentActivity else {
            return
        }
        switch configuration.kind {
        case .armRaise: activity = ArmRaiseActivity(configuration: configuration)
        case .elbowBend: activity = ElbowBendActivity(configuration: configuration)
        case .directionalReach: activity = DirectionalReachActivity(configuration: configuration)
        case .cup: activity = CupActivity(configuration: configuration)
        }
        if let viewport { _ = activity?.handle(.viewport(viewport)) }
        evidenceBoundary = now
        snapshot.activity = configuration
        snapshot.presentation = activity?.presentation
        snapshot.stage = .preparing
        snapshot.instruction = "session.cameraWait"
        deadline = nil
        guidance = nil
    }

    private mutating func observation(_ frame: TrackingObservation) {
        guard captureReady, frame.generation == generation,
            frame.timestamp.isFinite, frame.width > 0, frame.height > 0,
            now - frame.timestamp <= 0.3, now >= frame.timestamp
        else {
            return
        }
        guard lastTimestamp.map({ frame.timestamp > $0 }) ?? true else {
            return
        }
        lastTimestamp = frame.timestamp
        if let aspect, abs(aspect - frame.aspect) > 0.01 {
            recalibrate()
            pause()
        }
        aspect = frame.aspect
        updateReadiness()
        guard canProgress, snapshot.stage == .activity, frame.timestamp >= evidenceBoundary else {
            return
        }
        let old = activity?.presentation
        guard let result = activity?.handle(.observation(frame)) else {
            return
        }
        snapshot.presentation = result.presentation
        snapshot.instruction = result.presentation.instruction
        if result.status == .finished {
            record(.completed)
            return
        }
        if case .movement(let before) = old, case .movement(let after) = result.presentation,
            before.phase != after.phase {
            if after.phase == .targetCapture {
                snapshot.stage = .preparationWait
                snapshot.instruction = "parity.getReady"
                snapshot.seconds = 5
                deadline = now + 5
                return
            }
            if after.phase == .returnToStart, before.phase == .targetCapture {
                pendingPrefix = .target
                announce(result.presentation.instruction, timed: false)
                return
            }
        }
        if let seconds = result.presentation.countdownSeconds {
            if seconds > 0, old?.countdownSeconds != seconds {
                effects.append(.audio(UUID(), .countdown(seconds)))
            }
        } else if case .movement = result.presentation, old?.count != result.presentation.count {
            effects.append(.audio(UUID(), .count(result.presentation.count)))
        } else if case .movement = result.presentation,
            let previous = old?.guide, let next = result.presentation.guide,
            previous.targetActive, !next.targetActive {
            effects.append(.audio(UUID(), .target))
        } else if old?.instruction != result.presentation.instruction {
            announce(result.presentation.instruction, timed: false)
        }
    }

    private mutating func updateReadiness() {
        let ready =
            captureReady && previewReady && (lastTimestamp.map({ now - $0 <= 0.3 }) ?? false)
        if !ready {
            if waitingSince == nil {
                waitingSince = now
                beginSuspension()
                _ = activity?.handle(.suspend)
                effects.append(.cancelSpeech)
                guidance = nil
                speechTimeout = nil
            }
            snapshot.cameraWaiting = true
            return
        }
        if waitingSince != nil {
            waitingSince = nil
            if pausedSince == nil {
                endSuspension()
                _ = activity?.handle(.resume)
                if snapshot.stage == .instruction || snapshot.stage == .demonstration
                    || snapshot.stage == .feedback || snapshot.stage == .activity
                {
                    announce(snapshot.instruction, timed: snapshot.stage != .activity)
                }
            }
        }
        snapshot.cameraWaiting = false
        if snapshot.stage == .preparing, pausedSince == nil {
            endSuspension()
            _ = activity?.handle(.resume)
            if let configuration = progress.currentActivity {
                beginCards(.opening(configuration, includePositioning: positioningPending))
            }
        }
    }

    private mutating func tick() {
        guard canProgress else {
            return
        }
        if snapshot.stage == .activity {
            let before = activity?.presentation.countdownSeconds
            _ = activity?.handle(.tick(now))
            snapshot.presentation = activity?.presentation
            if let seconds = snapshot.presentation?.countdownSeconds, seconds > 0, seconds != before {
                effects.append(.audio(UUID(), .countdown(seconds)))
            }
        }
        if let timeout = speechTimeout, now >= timeout, let guidance {
            effects.append(.cancelSpeech)
            completeGuidance(guidance, available: false)
        }
        if let deadline, now >= deadline {
            self.deadline = nil
            switch snapshot.stage {
            case .instruction, .demonstration:
                if readingComplete {
                    advanceCard()
                } else {
                    self.deadline = deadline
                }
            case .preparationWait:
                enterActivity()
            case .feedback:
                if case .feedback(let request) = progress.stage {
                    progress.finishFeedback(request: request, at: now, date: Date())
                    if case .rest = progress.stage {
                        snapshot.stage = .rest
                        snapshot.instruction = "session.rest"
                        announce("session.rest", timed: false)
                    }
                }
            default: break
            }
        }
        if snapshot.stage == .preparationWait, let deadline {
            snapshot.seconds = max(0, Int(ceil(deadline - now)))
        }
        if case .rest(let deadline) = progress.stage {
            snapshot.seconds = max(0, Int(ceil(deadline - now)))
            progress.tick(at: now)
            if progress.stage == .activity {
                selectActivity()
                updateReadiness()
            }
        } else if let deadline {
            snapshot.seconds = max(0, Int(ceil(deadline - now)))
        }
    }

    private mutating func announce(_ key: String, timed: Bool) {
        effects.append(.cancelSpeech)
        let id = UUID()
        guidance = id
        narrationComplete = false
        guidanceStartedAt = now
        readingComplete = snapshot.stage != .instruction && snapshot.stage != .demonstration
        speechTimeout = now + (snapshot.stage == .feedback ? 45 : (timed ? (guidancePlan?.watchdog ?? 20) : 20))
        if timed { deadline = nil }
        snapshot.instruction = key
        if let prefix = pendingPrefix {
            pendingPrefix = nil
            effects.append(.audio(id, .guidance(prefix: prefix, key: key)))
        } else {
            effects.append(.speak(id, key))
        }
    }

    private mutating func completeGuidance(_ id: UUID, available: Bool = true) {
        guard canProgress, guidance == id else {
            return
        }
        narrationComplete = true
        speechTimeout = nil
        if snapshot.stage == .activity {
            _ = activity?.handle(.guidanceCompleted(now))
        }
        scheduleGuidanceAdvance()
        if !available, snapshot.stage == .instruction, guidancePlan?.quietDelay == 1 {
            deadline = max(guidanceStartedAt + (guidancePlan?.watchdog ?? 20), now + 12)
        }
    }

    private mutating func scheduleGuidanceAdvance() {
        guard canProgress, narrationComplete, deadline == nil else {
            return
        }
        switch snapshot.stage {
        case .instruction: deadline = now + (guidancePlan?.quietDelay ?? 3)
        case .demonstration: deadline = now + 8
        case .feedback: deadline = max(now, feedbackEnteredAt + 2)
        default: break
        }
    }

    private mutating func beginCards(_ plan: SessionGuidance) {
        guidancePlan = plan
        cardIndex = 0
        showCard()
    }

    private mutating func showCard() {
        guard let plan = guidancePlan, plan.cards.indices.contains(cardIndex) else { return }
        let card = plan.cards[cardIndex]
        snapshot.stage = card.demonstration ? .demonstration : .instruction
        snapshot.presentation = activity?.presentation
        announce(card.key, timed: true)
    }

    private mutating func advanceCard() {
        guard let plan = guidancePlan else { return }
        cardIndex += 1
        if positioningPending, cardIndex == 1 {
            positioningPending = false
        }
        if cardIndex < plan.cards.count {
            showCard()
            return
        }
        guidance = nil
        speechTimeout = nil
        switch plan.destination {
        case .capture:
            snapshot.stage = .preparationWait
            snapshot.instruction = "parity.getReady"
            snapshot.seconds = 5
            deadline = now + 5
        case .activity, .returnToStart:
            enterActivity()
        }
    }

    private mutating func enterActivity() {
        snapshot.stage = .activity
        evidenceBoundary = now
        snapshot.instruction = activity?.presentation.instruction ?? "session.holdStart"
        announce(snapshot.instruction, timed: false)
    }

    private var cupOutcomes: [CupMilestone]? {
        if case .cup(let value) = activity?.presentation { return value.outcomes }
        return nil
    }

    private var practicedSeconds: Double {
        switch activity?.presentation {
        case .reach(let value): return value.practiceSeconds
        case .timed(let value): return value.seconds
        default: return 0
        }
    }

    private mutating func record(_ outcome: ActivityOutcome) {
        guard progress.stage == .activity else {
            return
        }
        if pausedSince != nil {
            pausedSince = nil
            endSuspension()
            _ = activity?.handle(.resume)
        } else {
            progress.resume(at: now)
        }
        let presentation = activity?.presentation
        let reach: ReachSnapshot?
        if case .reach(let value) = presentation { reach = value } else { reach = nil }
        progress.record(
            execution: progress.executionID, outcome: outcome,
            completedWork: presentation?.count ?? 0, reachOutcomes: reach?.outcomes ?? [],
            skippedReachSteps: reach?.caregiverSkippedSteps,
            practiceSeconds: practicedSeconds,
            cupOutcomes: cupOutcomes)
        effects.append(.checkpoint(checkpoint))
        snapshot.stage = .feedback
        feedbackEnteredAt = now
        if outcome == .completed, case .movement = presentation, let count = presentation?.count, count > 0 {
            pendingPrefix = .count(count)
        }
        snapshot.instruction = outcome == .skipped ? "session.skipped" : "session.feedback"
        snapshot.assistanceKey = nil
        if canProgress { announce(snapshot.instruction, timed: true) }
    }

    private mutating func commandReceived(_ command: SessionCommand) {
        switch command {
        case .pause:
            snapshot.assistanceKey = nil
            pause()
        case .resume:
            guard pausedSince != nil else {
                return
            }
            pausedSince = nil
            if !snapshot.cameraWaiting {
                endSuspension()
                _ = activity?.handle(.resume)
            }
            if canProgress {
                announce(
                    snapshot.instruction,
                    timed: snapshot.stage == .instruction || snapshot.stage == .demonstration
                        || snapshot.stage == .feedback)
            }
            snapshot.assistanceKey = nil
        case .stop:
            if progress.stage == .activity {
                progress.resume(at: now)
                let reach: ReachSnapshot?
                if case .reach(let value) = activity?.presentation {
                    reach = value
                } else {
                    reach = nil
                }
                progress.record(
                    execution: progress.executionID,
                    outcome: .interrupted,
                    completedWork: activity?.presentation.count ?? 0,
                    reachOutcomes: reach?.outcomes ?? [],
                    skippedReachSteps: reach?.caregiverSkippedSteps,
                    practiceSeconds: practicedSeconds,
                    cupOutcomes: cupOutcomes
                )
            }
            progress.finalize(stopped: true, date: Date())
        case .timedPractice:
            guard let configuration = progress.currentActivity,
                configuration.kind == .armRaise || configuration.kind == .elbowBend,
                progress.stage == .activity, pausedSince != nil else { return }
            activity = TimedPracticeActivity(configuration: configuration, duration: progress.routine.practiceSeconds)
            snapshot.presentation = activity?.presentation
            snapshot.stage = .activity
            snapshot.instruction = "session.timedPractice"
            evidenceBoundary = now
        case .skip:
            record(.skipped)
        case .retryCalibration:
            recalibrate()
        case .repeatInstruction:
            if canProgress {
                announce(
                    snapshot.instruction,
                    timed: snapshot.stage == .instruction || snapshot.stage == .demonstration
                        || snapshot.stage == .feedback)
            }
        case .help:
            pause()
            snapshot.assistanceKey = currentAssistanceKey
        case .redo:
            routeActivityCommand(.redo)
        case .adjustTarget:
            routeActivityCommand(.adjustTarget)
        case .retryStep:
            routeActivityCommand(.retryStep)
        case .skipStep:
            routeActivityCommand(.skipStep)
        }
    }

    private var currentAssistanceKey: String? {
        switch progress.currentActivity?.kind {
        case .armRaise: return "session.assistance.armRaise"
        case .elbowBend: return "session.assistance.elbowBend"
        case .directionalReach: return "session.assistance.reach"
        case .cup: return "session.assistance.cup"
        case nil: return nil
        }
    }

    private mutating func routeActivityCommand(_ command: ActivityCommand) {
        guard progress.stage == .activity,
            snapshot.stage == .activity,
            var currentActivity = activity
        else {
            return
        }
        let transition = currentActivity.handle(.command(command, at: now))
        activity = currentActivity
        snapshot.presentation = transition.presentation
        snapshot.instruction = transition.presentation.instruction
        snapshot.assistanceKey = nil
        if transition.status == .finished {
            record(.completed)
            return
        }
        if canProgress {
            announce(snapshot.instruction, timed: false)
        }
    }

    private mutating func pause() {
        guard pausedSince == nil else {
            return
        }
        pausedSince = now
        beginSuspension()
        _ = activity?.handle(.suspend)
        effects.append(.cancelSpeech)
        guidance = nil
        speechTimeout = nil
    }

    private mutating func beginSuspension() {
        if suspensionSince == nil { suspensionSince = now }
        progress.pause(at: now)
    }

    private mutating func endSuspension() {
        evidenceBoundary = now
        if let since = suspensionSince, let deadline {
            self.deadline = deadline + now - since
        }
        suspensionSince = nil
        progress.resume(at: now)
    }

    private mutating func recalibrate() {
        guard progress.stage == .activity else {
            return
        }
        evidenceBoundary = now
        progress.retryExecution()
        _ = activity?.handle(.recalibrate)
        snapshot.presentation = activity?.presentation
        snapshot.stage = .preparing
        snapshot.instruction = "session.cameraWait"
        guidance = nil
        deadline = nil
        speechTimeout = nil
        effects.append(.cancelSpeech)
    }
}
