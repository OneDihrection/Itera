//
//  SessionEngine.swift
//  Tuntun
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
    /// A condition that refuses Resume became active or cleared. A newly active one pauses.
    case blocked(Suspension.Blocker, Bool)
}

enum SessionEffect {
    case speak(UUID, String)
    /// Stops narration at once: pause, stop, recalibration and the end of the session.
    case cancelSpeech
    /// The session moved on and the next cue replaces the current one: the narration finishes or
    /// fades out before it, never a hard cut (`SessionAudioService.handOffSpeech`).
    case handOffSpeech
    case audio(UUID, SessionAudioCue)
    case checkpoint(SessionCheckpoint)
    case finalize(SessionSummary)
    /// Key-repetition skeletons for one set, saved beside the session summary.
    case saveKeyReps(sessionID: UUID, ActivityKeyReps)
    /// Keeps the privacy-filtered video of a repetition that was just credited.
    case keepRepClip(KeyRepClipRequest)
}

struct SessionSnapshot {
    enum Stage { case preparing, preparationWait, instruction, demonstration, activity, feedback, rest, summary }
    var guidanceID: UUID?
    var stage: Stage = .preparing
    var instruction = "session.cameraWait"
    var presentation: ActivityPresentation?
    var activity: SessionActivity?
    /// The side exercising now. It follows the turns of an activity that alternates sides and is
    /// the configured side otherwise.
    var activeSide: TherapySide?
    var activityCount = 0
    var index = 0
    var setNumber = 1
    var seconds = 0
    var restBreath: RestBreath?
    var guidedSetBreathing: BreathingRest?
    var usesArmRaiseScript = false
    /// The recorded arm-raise set summary just spoken, or nil when the counts did not match
    /// its numbers and the general ending was used.
    var armRaiseSummaryKey: String?
    /// Retained through summary, when `activity` becomes nil, to select the correct recordings.
    var armRaiseScriptSide = TherapySide.left
    var armRaiseNarrationPrefix: String { ArmRaiseGuidance.prefix(for: armRaiseScriptSide) }
    var paused = false
    /// Whether the shown countdown's clock is running. Preparation and the pre-practice countdown
    /// show their full value while the cue is still being spoken, before their deadline starts.
    var countdownRunning = false
    /// The pre-practice countdown, which the session runs for every activity.
    var countdown: PracticeCountdown?
    /// True while "calibration complete" is the cue being spoken, before the countdown cue.
    var speaksCalibrationComplete = false
    var assistanceKey: String?
    var cameraWaiting = true
    var summary: SessionSummary?
    /// Every set recorded so far, so set pages can show earlier sets before the summary exists.
    var results: [SessionActivityResult] = []
}

struct PracticeCountdown: Equatable {
    let seconds: Int
    let running: Bool
}

struct SessionTransition {
    let snapshot: SessionSnapshot
    let effects: [SessionEffect]
}

/// One serialized owner of ordering, asynchronous identities, and terminal bookkeeping.
struct SessionEngine {
    private var progress: SessionProgress
    private let scriptedArmRaise: Bool
    private var pendingScriptMovement: String?
    private var lastScriptHoldCount = ""
    private var activity: (any TherapyActivity)?
    private(set) var snapshot = SessionSnapshot()
    private var effects: [SessionEffect] = []
    /// Set when an activity entered its countdown during the current event, so the countdown cue
    /// is announced once at the end of the turn if nothing announced it sooner.
    private var countdownRequestedThisTurn = false
    private var now = 0.0
    private var lastTimestamp: Double?
    private var generation: UUID?
    private var aspect: Double?
    private var previewReady = false
    private var captureReady = false
    /// The cue being spoken: its identity, narration and reading state, and watchdog.
    private var gate: GuidanceGate?
    /// The single source of truth for where the session is; `snapshot.stage` mirrors it.
    private var stage: SessionStage = .preparing
    /// Pause and camera-wait reasons, resume blockers, and the open frozen interval.
    private var suspension = Suspension()
    private var viewport: TherapyViewport?
    private var began = false
    private var evidenceBoundary = 0.0
    private var guidancePlan: SessionGuidance?
    private var positioningPending = true
    private var pendingPrefix: SessionAudioCue?
    /// The side cue of an alternating arm exercise is being spoken; the new side's instruction
    /// follows it.
    private var instructionFollowsSideCue = false
    /// Limits live towel speech to the first cue and a stuck reminder.
    private var towelSpeech = TowelSpeechPolicy()
    /// The current set still owes "calibration complete" before its countdown cue.
    private var calibrationCompletionPending = false
    /// The cue being spoken is "calibration complete"; its completion announces the countdown cue.
    private var calibrationCueSpeaking = false
    /// Per-repetition metrics and key-repetition skeletons for the current set.
    private var recorder: KeyRepRecorder?
    /// When a stale-frame rejection was last logged, so the log stays at most one line every 3 s.
    private var lastStaleLog = -Double.infinity

    /// How long the session keeps guidance running without a scoring-fresh frame before it waits
    /// for the camera. Scoring still rejects frames older than 300 ms; this only stops a brief
    /// inference or main-thread hitch from cancelling narration and replaying it on every gap.
    static let cameraWaitGrace = 1.0

    /// How long a demonstration card stays after its narration, so the looping clip can be seen
    /// once more without the voice. Kept short: the clip already played under the narration.
    static let demonstrationHold = 3.0

    init(routine: Routine = .demo(), date: Date = Date(), scriptedArmRaise: Bool = false) {
        self.scriptedArmRaise = scriptedArmRaise
        progress = SessionProgress(routine: routine, startedAt: date)
        selectActivity()
    }

    // MARK: - Events

    mutating func handle(_ event: SessionEvent, at time: Double) -> SessionTransition {
        effects = []
        countdownRequestedThisTurn = false
        guard time.isFinite else {
            return transition
        }
        now = max(now, time)
        if !began {
            began = true
            effects.append(.checkpoint(checkpoint))
        }
        if stage == .summary {
            return transition
        }
        switch event {
        case .command(let command): commandReceived(command)
        case .viewport(let value):
            viewport = value
            forward(.viewport(value))
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
        case .blocked(let blocker, let active):
            if suspension.setBlocker(blocker, active) {
                snapshot.assistanceKey = nil
                pause()
            }
        case .observation(let frame): observation(frame)
        case .guidanceCompleted(let id, let available): completeGuidance(id, available: available)
        case .readingChanged(let id, let complete):
            guard canProgress, gate?.reading(id, done: complete) == true else {
                return transition
            }
            scheduleGuidanceAdvance()
        case .tick:
            updateReadiness()
            tick()
        }
        if canProgress, snapshot.stage == .activity,
           snapshot.presentation?.countdownLength != nil,
           countdownRequestedThisTurn, !awaitingCountdownCue {
            announcePracticeCountdown()
        }
        // A due countdown ends on whichever event arrives first, so it never shows 0.
        finishCountdownIfDue()
        if canProgress, var countdown, let seconds = countdown.takeAnnouncement(at: now) {
            self.countdown = countdown
            effects.append(.audio(UUID(), .countdown(seconds)))
        }
        snapshot.guidanceID = gate?.id
        snapshot.countdownRunning = countdownClockRunning
        snapshot.countdown = countdown.map {
            PracticeCountdown(seconds: $0.seconds(at: now), running: $0.isRunning)
        }
        snapshot.speaksCalibrationComplete = calibrationCueSpeaking
        snapshot.activity = progress.currentActivity
        snapshot.index = progress.index
        snapshot.setNumber = progress.setNumber
        snapshot.activityCount = progress.routine.activities.count
        snapshot.paused = suspension.isPaused
        snapshot.results = progress.results
        snapshot.summary = progress.summary
        snapshot.guidedSetBreathing = stage.breathing
        if let summary = progress.summary, stage != .summary {
            enter(.summary)
            effects.append(.cancelSpeech)
            effects.append(.finalize(summary))
            if !snapshot.usesArmRaiseScript || summary.stopped {
                effects.append(.audio(UUID(), .closing(completed: !summary.stopped && summary.results.allSatisfy { $0.outcome == .completed })))
            }
        }
        return transition
    }

    // MARK: - Arm-raise script

    private var practiceCountdownKey: String {
        guard snapshot.usesArmRaiseScript else {
            return "calibration.countdown"
        }
        return progress.setNumber == 1 ? snapshot.armRaiseNarrationPrefix + "countdown.first" : snapshot.armRaiseNarrationPrefix + "countdown.next"
    }

    private var currentScriptInstruction: String {
        if snapshot.usesArmRaiseScript, snapshot.stage == .activity,
           !calibrationCueSpeaking, case .movement(let movement) = activity?.presentation {
            return ArmRaiseGuidance.movementKey(movement, set: progress.setNumber, goal: scriptGoal, side: snapshot.armRaiseScriptSide)
        }
        return snapshot.instruction
    }

    /// Repetitions per set of the current arm-raise script, which chooses its recorded lines.
    private var scriptGoal: Int {
        progress.currentActivity?.goal ?? ScriptedRepetitions.recordedRepetitions
    }

    /// The recorded set summary when its numbers are true; otherwise Marizka says the set's
    /// repetitions before the general set or exercise ending.
    private mutating func scriptedSummary(count: Int) -> String {
        let sets = progress.currentActivity?.sets ?? 1
        snapshot.armRaiseSummaryKey = ArmRaiseGuidance.summaryKey(
            setNumber: progress.setNumber,
            sets: sets,
            goal: scriptGoal,
            side: snapshot.armRaiseScriptSide
        )
        if let key = snapshot.armRaiseSummaryKey {
            return key
        }

        if count > 0 {
            pendingPrefix = .count(count)
        }
        return progress.setNumber < sets ? "session.good" : "session.feedback"
    }

    /// Spoken seconds follow fresh, accepted hold progress. They never run from a wall timer.
    private mutating func speakScriptHoldCount(_ movement: MovementSnapshot) {
        guard gate?.narrated == true, movement.progress > 0, movement.progress < 1 else {
            lastScriptHoldCount = ""
            return
        }
        let seconds = max(1, Int(ceil(3 * (1 - movement.progress))))
        let identity = "\(progress.setNumber)-\(movement.phase)-\(movement.count)-\(movement.instruction)-\(seconds)"
        guard identity != lastScriptHoldCount else {
            return
        }
        lastScriptHoldCount = identity
        effects.append(.audio(UUID(), .holdSecond(seconds)))
    }

    // MARK: - Stages

    private var transition: SessionTransition {
        SessionTransition(snapshot: snapshot, effects: effects)
    }
    private var checkpoint: SessionCheckpoint {
        SessionCheckpoint(
            id: progress.id, routine: progress.routine, startedAt: progress.startedAt,
            results: progress.results)
    }
    private var canProgress: Bool { !suspension.isPaused && !snapshot.cameraWaiting }

    /// The practice stage's countdown; nil in every other stage.
    private var countdown: Countdown? {
        get {
            guard case .practice(let practice) = stage else {
                return nil
            }
            return practice.countdown
        }
        set {
            guard case .practice(var practice) = stage else {
                return
            }
            practice.countdown = newValue
            stage = .practice(practice)
        }
    }

    /// The activity waits through a countdown whose cue has not finished yet: frames and ticks
    /// are held back from it until the countdown starts.
    private var awaitingCountdownCue: Bool {
        countdown.map { !$0.isRunning } ?? false
    }

    private mutating func selectActivity() {
        calibrationCompletionPending = false
        guard let configuration = progress.currentActivity else {
            return
        }
        snapshot.usesArmRaiseScript = scriptedArmRaise && ArmRaiseGuidance.applies(to: configuration)
        snapshot.armRaiseScriptSide = configuration.side
        pendingScriptMovement = nil
        lastScriptHoldCount = ""
        recorder = KeyRepRecorder(activity: configuration)
        let scripted = snapshot.usesArmRaiseScript

        if configuration.alternatesSides {
            activity = AlternatingSidesActivity(configuration: configuration) { side in
                Self.makeActivity(side, scriptedGuidance: scripted)
            }
        } else {
            activity = Self.makeActivity(configuration, scriptedGuidance: scripted)
        }

        if let viewport { forward(.viewport(viewport)) }
        evidenceBoundary = now
        snapshot.activity = configuration
        snapshot.activeSide = configuration.side
        snapshot.presentation = activity?.presentation
        enter(.preparing)
        snapshot.guidedSetBreathing = nil
        snapshot.instruction = "session.cameraWait"
        gate = nil
    }

    private static func makeActivity(_ configuration: SessionActivity, scriptedGuidance: Bool) -> (any TherapyActivity)? {
        switch configuration.kind {
        case .foldTowel:
            return FoldTowelActivity(configuration: configuration)
        case .armRaise:
            return ArmRaiseActivity(configuration: configuration, scriptedGuidance: scriptedGuidance)
        case .elbowBend:
            return ElbowBendActivity(configuration: configuration)
        case .directionalReach:
            return DirectionalReachActivity(configuration: configuration)
        case .sitToStand, .crossMidline, .externalRotation, .internalRotation, .shoulderFlexion:
            // Balancing exercises run on their own screens. Sit-to-stand stays only so routines
            // saved before Trunk Control moved there still decode; nothing offers it any more.
            return nil
        }
    }

    /// Sends an event to the current activity and notes the facts the engine reacts to at the end
    /// of the turn.
    @discardableResult
    private mutating func forward(_ event: ActivityEvent) -> ActivityTransition? {
        guard let transition = activity?.handle(event) else {
            return nil
        }
        noteFacts(transition.facts)
        dropCountdownIfAbandoned(transition.presentation)
        return transition
    }

    /// A caregiver command or recalibration can take the activity out of its countdown.
    private mutating func dropCountdownIfAbandoned(_ presentation: ActivityPresentation) {
        if presentation.countdownLength == nil, countdown != nil {
            countdown = nil
        }
    }

    /// Ends a running countdown that is due, on whichever event comes first, and starts practice
    /// the same way for every activity: the practice cue is shown, and the arm-raise script speaks
    /// its first movement line. Frames from before this moment are not scored.
    private mutating func finishCountdownIfDue() {
        guard canProgress, let countdown, countdown.isFinished(at: now) else {
            return
        }
        self.countdown = nil
        evidenceBoundary = now
        forward(.countdownFinished(now))
        guard let presentation = activity?.presentation else {
            return
        }
        snapshot.presentation = presentation
        snapshot.instruction = presentation.instruction
        // Alternating practice names the side that starts.
        if progress.currentActivity?.alternatesSides == true, let side = snapshot.activeSide {
            announce(sideCueKey(side), timed: false)
            return
        }
        if snapshot.usesArmRaiseScript, case .movement(let movement) = presentation {
            announce(
                ArmRaiseGuidance.movementKey(movement, set: progress.setNumber, goal: scriptGoal, side: snapshot.armRaiseScriptSide),
                timed: false
            )
        }
    }

    private mutating func noteFacts(_ facts: [ActivityFact]) {
        if facts.requestsCountdown {
            countdownRequestedThisTurn = true
        }

        if let side = facts.changedSide {
            snapshot.activeSide = side
        }
    }

    /// The side that took over has not captured its positions yet.
    private static func awaitsCalibration(_ presentation: ActivityPresentation) -> Bool {
        switch presentation {
        case .movement(let value):
            return value.phase == .startCapture
        case .reach(let value):
            return value.phase == .setup
        case .towel, .timed:
            return false
        }
    }

    /// Introduces the next side's calibration as readiness does the first side's: the intro, then
    /// that side's opening and demonstration cards, then capture. "Calibration complete" stays
    /// owed until the countdown after the last side.
    private mutating func beginSideCalibration() {
        enter(.opening(.init(step: .calibrationIntro)))
        snapshot.seconds = 0
        announce("calibration.intro", timed: false)
    }

    /// The cue naming the side that takes over in an alternating activity.
    private func sideCueKey(_ side: TherapySide) -> String {
        progress.currentActivity?.kind == .foldTowel
            ? "recovery." + side.rawValue
            : "session.switchArm." + side.rawValue
    }

    /// The only place the stage changes. The cue being spoken is left alone: it belongs to the
    /// narration, and the next `announce` replaces it.
    private mutating func enter(_ next: SessionStage) {
        calibrationCueSpeaking = false
        instructionFollowsSideCue = false
        stage = next
        snapshot.stage = next.presentation
    }

    private mutating func beginNextSet(recalibrating: Bool) {
        forward(.resume)
        forward(.nextSet)
        if recalibrating {
            forward(.recalibrate)
            snapshot.presentation = activity?.presentation
            enter(.preparing)
            gate = nil
            updateReadiness()
            return
        }
        snapshot.presentation = activity?.presentation
        enter(.practice(.init()))
        evidenceBoundary = now
        announcePracticeCountdown()
    }

    // MARK: - Evidence and readiness

    private mutating func observation(_ frame: TrackingObservation) {
        // The tracking service delivers frames up to 0.8 s old, but scoring accepts only 0.3 s.
        // Frames in between still draw the live skeleton while the activity sees nothing, so log
        // them to tell a slow pipeline apart from a body the detector cannot see.
        if captureReady, frame.generation == generation, now - frame.timestamp > 0.3, now - lastStaleLog >= 3 {
            lastStaleLog = now
            LogManager.shared.warning("Session frame rejected as stale age=\(String(format: "%.3f", now - frame.timestamp))", category: .session)
        }

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
        guard canProgress, frame.timestamp >= evidenceBoundary else {
            return
        }
        guard snapshot.stage == .activity, !awaitingCountdownCue else {
            previewWhileGated(frame)
            return
        }
        finishCountdownIfDue()
        // Only the arm-raise script still compares cue keys across the event (Phase 6).
        let old = activity?.presentation
        let previousInstruction = snapshot.instruction
        guard let result = forward(.observation(frame)) else {
            return
        }
        let facts = result.facts
        snapshot.presentation = result.presentation
        snapshot.instruction = result.presentation.instruction
        let movingSide = progress.currentActivity?.alternatesSides == true ? snapshot.activeSide : nil
        if let clip = recorder?.observe(frame, presentation: result.presentation, side: movingSide) {
            effects.append(.keepRepClip(clip))
        }
        if result.status == .finished {
            record(.completed)
            if case .towel = result.presentation {
                effects.append(.audio(UUID(), .towelCompleted))
            }
            return
        }
        // The other side takes over: name it. A handover into the set's countdown is left to the
        // countdown cue, and the demonstration already shows the side.
        if let side = facts.changedSide, !facts.requestsCountdown {
            // A side still to calibrate gets the whole calibration intro the first side had.
            if Self.awaitsCalibration(result.presentation) {
                beginSideCalibration()
                return
            }
            announce(sideCueKey(side), timed: false)
            // The towel limits its live speech; arm exercises then say what the new side does.
            instructionFollowsSideCue = progress.currentActivity?.kind != .foldTowel
            return
        }
        if case .towel = result.presentation {
            // Live towel speech is limited by `towelSpeech` and runs from the tick, never from here.
            if facts.creditsRepetition {
                effects.append(.audio(UUID(), .towelCompleted))
            } else if facts.contains(.towelFolded) {
                effects.append(.audio(UUID(), .towelFold))
            } else if facts.contains(.towelGrabbed) {
                effects.append(.audio(UUID(), .towelGrab))
            }
            return
        }
        if snapshot.usesArmRaiseScript,
           case .movement(let after) = result.presentation {
            if pendingScriptMovement != nil {
                snapshot.instruction = previousInstruction
                return
            }
            let key = ArmRaiseGuidance.movementKey(after, set: progress.setNumber, goal: scriptGoal, side: snapshot.armRaiseScriptSide)
            if after.phase == .countdown {
                if facts.requestsCountdown {
                    announcePracticeCountdown()
                }
            } else if facts.creditsRepetition {
                if let praise = ArmRaiseGuidance.praiseKey(after: after.count, side: snapshot.armRaiseScriptSide) {
                    pendingScriptMovement = key
                    announce(praise, timed: false)
                } else {
                    // No recording praises this repetition: Marizka says its number, then the
                    // next movement cue follows in the same guidance.
                    pendingPrefix = .count(after.count)
                    announce(key, timed: false)
                }
            } else if case .movement(let before) = old,
                      ArmRaiseGuidance.movementKey(before, set: progress.setNumber, goal: scriptGoal, side: snapshot.armRaiseScriptSide) != key {
                announce(key, timed: false)
            } else {
                snapshot.instruction = key
            }
            speakScriptHoldCount(after)
            return
        }
        if case .movement = result.presentation {
            if facts.entered(.targetCapture) {
                enter(.opening(.init(step: .tryMovement)))
                snapshot.seconds = 0
                announce("calibration.try", timed: false)
                return
            }
            if facts.entered(.returnToStart, from: .targetCapture) {
                pendingPrefix = .target
                announce(result.presentation.instruction, timed: false)
                return
            }
        }
        if result.presentation.countdownLength != nil {
            if facts.requestsCountdown {
                announcePracticeCountdown()
            }
        } else if case .movement = result.presentation, facts.creditsRepetition {
            // Each accepted repetition is counted aloud.
            effects.append(.audio(UUID(), .count(result.presentation.count)))
        } else if case .movement = result.presentation, facts.contains(.targetReached) {
            effects.append(.audio(UUID(), .target))
        } else if facts.contains(.cueChanged(result.presentation.instruction)) {
            announce(result.presentation.instruction, timed: false)
        }
    }

    /// While a spoken cue holds scoring back, the activity still moves its drawn guide, so the
    /// patient keeps seeing the tracked joint, as Balancing does. The frame is never scored and
    /// its transition carries no facts, so nothing advances.
    private mutating func previewWhileGated(_ frame: TrackingObservation) {
        let gated: Bool

        switch stage {
        case .opening:
            gated = true
        case .practice:
            gated = awaitingCountdownCue
        case .preparing, .feedback, .rest, .summary:
            gated = false
        }

        guard gated,
              let transition = activity?.handle(.preview(frame)) else {
            return
        }

        snapshot.presentation = transition.presentation
    }

    private mutating func updateReadiness() {
        // Activities receive no frames during a gap, so holds freeze and no time is credited.
        let ready =
            captureReady
            && previewReady
            && (lastTimestamp.map({ now - $0 <= Self.cameraWaitGrace }) ?? false)
        if !ready {
            _ = suspend(.cameraWait)
            snapshot.cameraWaiting = true
            return
        }
        if suspension.remove(.cameraWait) {
            if !suspension.isPaused {
                resumeAfterSuspension()
                // Preparing replays nothing (its opening starts below), nor does a timed rest,
                // whose breath cue follows its own clock.
                if snapshot.stage == .instruction || snapshot.stage == .demonstration
                    || snapshot.stage == .feedback || snapshot.stage == .activity
                    || snapshot.stage == .preparationWait
                    || stage.breathing != nil
                {
                    replayStageCue(timed: snapshot.stage != .activity)
                }
            }
        }
        snapshot.cameraWaiting = false
        if snapshot.stage == .preparing, !suspension.isPaused {
            endSuspension()
            forward(.resume)
            if let configuration = progress.currentActivity {
                let plan = SessionGuidance.opening(
                    configuration,
                    side: snapshot.activeSide,
                    includePositioning: positioningPending
                )
                if snapshot.usesArmRaiseScript {
                    calibrationCompletionPending = true
                    enter(.opening(.init(step: .scriptedPosition)))
                    snapshot.seconds = 0
                    announce(snapshot.armRaiseNarrationPrefix + "calibration.position", timed: false)
                } else if plan.destination == .capture {
                    calibrationCompletionPending = true
                    enter(.opening(.init(step: .calibrationIntro)))
                    snapshot.seconds = 0
                    announce("calibration.intro", timed: false)
                } else {
                    beginCards(plan)
                }
            }
        }
    }

    // MARK: - Clock and deadlines

    private mutating func tick() {
        guard canProgress else {
            return
        }
        if snapshot.stage == .activity && !awaitingCountdownCue {
            finishCountdownIfDue()
            forward(.tick(now))
            snapshot.presentation = activity?.presentation
            if snapshot.usesArmRaiseScript, pendingScriptMovement == nil,
               case .movement(let movement) = snapshot.presentation,
               movement.phase != .countdown {
                let key = ArmRaiseGuidance.movementKey(movement, set: progress.setNumber, goal: scriptGoal, side: snapshot.armRaiseScriptSide)
                if snapshot.instruction != key {
                    announce(key, timed: false)
                }
            }
            if case .towel(let after) = snapshot.presentation {
                // Live narration is replaceable feedback, never a practice advancement gate.
                if towelSpeech.shouldSpeak(after, now: now) {
                    announce(after.instruction, timed: false)
                }
            }
        }
        if let gate, gate.expired(at: now) {
            effects.append(.cancelSpeech)
            completeGuidance(gate.id, available: false)
        }
        if let deadline = stage.advanceAt, now >= deadline {
            stage.advanceAt = nil
            switch stage {
            case .opening(let opening):
                if case .card = opening.step {
                    if gate?.read == true {
                        advanceCard()
                    } else {
                        stage.advanceAt = deadline
                    }
                } else {
                    enterActivity()
                }
            case .feedback(let feedback):
                finishFeedback(feedback)
            case .preparing, .practice, .rest, .summary:
                break
            }
        }
        if snapshot.stage == .preparationWait, let deadline = stage.advanceAt {
            snapshot.seconds = max(0, Int(ceil(deadline - now)))
        }
        if case .rest(let rest) = stage, var breathing = rest.breathing {
            let step = breathing.step
            breathing.tick(now)
            stage.breathing = breathing
            if breathing.finished {
                stage.breathing = nil
                _ = progress.advanceAfterRest()
                beginNextSet(recalibrating: rest.recalibrateBeforeNext)
            } else if step != breathing.step, let key = breathing.key {
                announce(snapshot.armRaiseNarrationPrefix + key, timed: false)
            }
            return
        }
        if case .rest(let rest) = stage, let deadline = rest.deadline {
            let remaining = max(0, deadline - now)
            snapshot.seconds = Int(ceil(remaining))
            if progress.hasNextSet, remaining > 0 {
                let breath = RestBreath(elapsed: progress.routine.restSeconds - remaining)
                if snapshot.restBreath?.phase != breath.phase {
                    announce(breath.phase.key, timed: false)
                }
                snapshot.restBreath = breath
            }
            guard now >= deadline else {
                return
            }
            if snapshot.restBreath != nil {
                snapshot.restBreath = nil
                effects.append(.handOffSpeech)
            }
            switch progress.advanceAfterRest() {
            case .set:
                beginNextSet(recalibrating: rest.recalibrateBeforeNext)
            case .activity:
                selectActivity()
                updateReadiness()
            }
        } else if let deadline = stage.advanceAt {
            snapshot.seconds = max(0, Int(ceil(deadline - now)))
        }
    }

    /// After the feedback cue: the session ends after the routine's last set; otherwise it rests,
    /// with scripted breathing between the arm-raise script's sets and a timed rest elsewhere.
    private mutating func finishFeedback(_ feedback: SessionStage.Feedback) {
        guard !progress.finishIfLastSet(date: Date()) else {
            return
        }

        let breathing: BreathingRest?
        if snapshot.usesArmRaiseScript, progress.hasNextSet {
            breathing = BreathingRest(
                opensAfterFirstSet: progress.setNumber == 1,
                minimumSeconds: progress.routine.restSeconds
            )
        } else {
            breathing = nil
        }

        enter(.rest(.init(
            deadline: breathing == nil ? now + max(0, progress.routine.restSeconds) : nil,
            breathing: breathing,
            recalibrateBeforeNext: feedback.recalibrateBeforeNext
        )))
        snapshot.instruction = "session.rest"

        if let key = breathing?.key {
            announce(snapshot.armRaiseNarrationPrefix + key, timed: false)
        } else if !progress.hasNextSet {
            announce("session.rest", timed: false)
        }
    }

    /// Preparation starts its deadline when its narration ends, and the practice countdown when its
    /// cue ends, including after a resume. Rest has no wait.
    private var countdownClockRunning: Bool {
        switch snapshot.stage {
        case .preparationWait:
            return stage.advanceAt != nil
        case .activity:
            return countdown?.isRunning ?? false
        case .rest:
            return true
        default:
            return false
        }
    }

    // MARK: - Narration

    private mutating func announce(_ key: String, timed: Bool) {
        let liveTowel = snapshot.stage == .activity
            && progress.currentActivity?.kind == .foldTowel
            && snapshot.presentation?.countdownLength == nil
        calibrationCueSpeaking = false
        // A newer cue replaces the side cue, and with it the instruction owed after it.
        instructionFollowsSideCue = false
        if timed || liveTowel || snapshot.usesArmRaiseScript {
            effects.append(.handOffSpeech)
        }
        let id = UUID()
        gate = GuidanceGate(
            id: id,
            startedAt: now,
            watchdog: watchdogSeconds(timed: timed),
            read: !cueShownOnCard
        )
        if timed || snapshot.stage == .preparationWait { stage.advanceAt = nil }
        snapshot.instruction = key
        if let prefix = pendingPrefix {
            pendingPrefix = nil
            effects.append(.audio(id, .guidance(prefix: prefix, key: key)))
        } else {
            effects.append(.speak(id, key))
        }
    }

    /// How long a cue may stay unfinished before it counts as spoken: scripted lines and feedback
    /// get 45 s, opening cards their plan's watchdog, everything else 20 s.
    private func watchdogSeconds(timed: Bool) -> Double {
        if snapshot.usesArmRaiseScript || snapshot.stage == .feedback {
            return 45
        }

        guard timed else {
            return 20
        }

        return guidancePlan?.watchdog ?? 20
    }

    /// Sets up the activity's countdown, waiting for its cue, and speaks that cue: "calibration
    /// complete" first when the set still owes it.
    private mutating func announcePracticeCountdown() {
        countdown = activity?.presentation.countdownLength.map { Countdown(length: $0) }
        if calibrationCompletionPending {
            calibrationCompletionPending = false
            announce(snapshot.usesArmRaiseScript ? snapshot.armRaiseNarrationPrefix + "calibration.complete" : "calibration.complete", timed: false)
            calibrationCueSpeaking = true
        } else {
            announce(practiceCountdownKey, timed: false)
        }
    }

    private mutating func completeGuidance(_ id: UUID, available: Bool = true) {
        guard canProgress, gate?.complete(id) == true else {
            return
        }
        if snapshot.usesArmRaiseScript {
            if stage.breathing != nil {
                stage.breathing?.guidanceCompleted()
                return
            }
            if snapshot.stage == .preparationWait, case .opening(let opening) = stage {
                if opening.step == .scriptedPosition {
                    enter(.opening(.init(step: .scriptedStart)))
                    announce(snapshot.armRaiseNarrationPrefix + "calibration.start", timed: false)
                } else {
                    enter(.practice(.init()))
                    evidenceBoundary = now
                    forward(.guidanceCompleted(now))
                }
                return
            }
            if let pendingScriptMovement {
                self.pendingScriptMovement = nil
                announce(pendingScriptMovement, timed: false)
                return
            }
        }
        if snapshot.stage == .preparationWait, case .opening(let opening) = stage {
            if opening.step == .calibrationIntro, let configuration = progress.currentActivity {
                beginCards(.opening(configuration, side: snapshot.activeSide, includePositioning: positioningPending))
                return
            }
            stage.advanceAt = now
        }
        if snapshot.stage == .activity {
            if instructionFollowsSideCue {
                instructionFollowsSideCue = false
                if let instruction = activity?.presentation.instruction {
                    announce(instruction, timed: false)
                    return
                }
            }
            // A live towel cue may finish late, fail, or never finish. None changes mechanics.
            if case .towel(let towel) = snapshot.presentation, towel.phase == .practice {
                return
            }
            if awaitingCountdownCue {
                if calibrationCueSpeaking {
                    announce(practiceCountdownKey, timed: false)
                    return
                }
                let startedAt = now
                countdown?.start(at: startedAt)
            }
            forward(.guidanceCompleted(now))
        }
        scheduleGuidanceAdvance()
        if !available, snapshot.stage == .instruction, guidancePlan?.quietDelay == 1 {
            stage.advanceAt = max((gate?.startedAt ?? now) + (guidancePlan?.watchdog ?? 20), now + 12)
        }
    }

    private mutating func scheduleGuidanceAdvance() {
        guard canProgress, gate?.narrated == true, stage.advanceAt == nil else {
            return
        }
        switch stage {
        case .opening(let opening):
            guard case .card(_, let demonstration) = opening.step else {
                return
            }
            stage.advanceAt = demonstration
                ? now + Self.demonstrationHold
                : now + (guidancePlan?.quietDelay ?? SessionGuidance.defaultQuietDelay)
        case .feedback(let feedback):
            stage.advanceAt = max(now, feedback.enteredAt + 2)
        case .preparing, .practice, .rest, .summary:
            break
        }
    }

    // MARK: - Opening

    private mutating func beginCards(_ plan: SessionGuidance) {
        guidancePlan = plan
        showCard(0)
    }

    private mutating func showCard(_ index: Int) {
        guard let plan = guidancePlan, plan.cards.indices.contains(index) else { return }
        let card = plan.cards[index]
        enter(.opening(.init(step: .card(index: index, demonstration: card.demonstration))))
        snapshot.presentation = activity?.presentation
        announce(card.key, timed: true)
    }

    private mutating func advanceCard() {
        guard let plan = guidancePlan,
              case .opening(let opening) = stage,
              case .card(let index, _) = opening.step
        else {
            return
        }
        let next = index + 1
        if positioningPending, next == 1 {
            positioningPending = false
        }
        if next < plan.cards.count {
            showCard(next)
            return
        }
        gate = nil
        switch plan.destination {
        case .capture:
            enter(.opening(.init(step: .tryMovement)))
            snapshot.seconds = 0
            announce("calibration.try", timed: false)
        case .activity, .returnToStart:
            enterActivity()
        }
    }

    private mutating func enterActivity() {
        enter(.practice(.init()))
        evidenceBoundary = now
        snapshot.instruction = snapshot.usesArmRaiseScript
            ? currentScriptInstruction
            : (activity?.presentation.instruction ?? "session.holdStart")
        if case .towel = activity?.presentation {
            // The towel activity already has a countdown while its demonstration is on screen.
            announcePracticeCountdown()
            return
        }
        announce(snapshot.instruction, timed: false)
    }

    // MARK: - Recording

    private var practicedSeconds: Double {
        switch activity?.presentation {
        case .reach(let value): return value.practiceSeconds
        case .timed(let value): return value.seconds
        default: return 0
        }
    }

    /// Records the current set's outcome and moves to its feedback. Skip, completion and the
    /// caregiver's activity commands come through here; Stop records through `recordResult` and
    /// ends the session instead.
    private mutating func record(_ outcome: ActivityOutcome) {
        guard stage.isRecordable else {
            return
        }
        // Recording never lifts a suspension: a skip while paused or waiting for the camera stays
        // suspended, and its feedback cue plays after Resume.
        pendingScriptMovement = nil
        // A cue owed to this set is not carried into the next one.
        calibrationCompletionPending = false
        let presentation = activity?.presentation
        guard recordResult(outcome) else {
            return
        }
        effects.append(.checkpoint(checkpoint))
        enter(.feedback(.init(enteredAt: now)))
        var countsRepetitions = false
        switch presentation {
        case .movement, .towel: countsRepetitions = true
        default: break
        }
        if !snapshot.usesArmRaiseScript, outcome == .completed, countsRepetitions, let count = presentation?.count, count > 0 {
            pendingPrefix = .count(count)
        }
        if snapshot.usesArmRaiseScript, outcome == .completed {
            snapshot.instruction = scriptedSummary(count: presentation?.count ?? 0)
        } else {
            snapshot.instruction = outcome == .skipped ? "session.skipped" : "session.feedback"
        }
        snapshot.assistanceKey = nil
        if canProgress { announce(snapshot.instruction, timed: true) }
    }

    /// Adds the current set's result with its evidence. Returns false when the set already has one.
    private mutating func recordResult(_ outcome: ActivityOutcome) -> Bool {
        let presentation = activity?.presentation
        let reach: ReachSnapshot?
        if case .reach(let value) = presentation {
            reach = value
        } else {
            reach = nil
        }

        return progress.record(
            outcome: outcome,
            completedWork: presentation?.count ?? 0,
            reachOutcomes: reach?.outcomes ?? [],
            skippedReachSteps: reach?.caregiverSkippedSteps,
            practiceSeconds: practicedSeconds,
            repMetrics: takeRecording(for: outcome)
        )
    }

    /// Emits the set's key repetitions for saving and returns its per-repetition metrics, then
    /// starts a fresh recorder for the next set. Skipped work and sets without a credited
    /// repetition record nothing.
    private mutating func takeRecording(for outcome: ActivityOutcome) -> [RepMetrics]? {
        defer {
            recorder = progress.currentActivity.map { KeyRepRecorder(activity: $0) }
        }

        guard outcome != .skipped,
              let recorder,
              !recorder.metrics.isEmpty
        else {
            return nil
        }

        if let keyReps = recorder.keyReps(executionID: progress.executionID, setNumber: progress.setNumber) {
            effects.append(.saveKeyReps(sessionID: progress.id, keyReps))
        }

        return recorder.metrics
    }

    // MARK: - Commands

    private mutating func commandReceived(_ command: SessionCommand) {
        switch command {
        case .pause:
            snapshot.assistanceKey = nil
            pause()
        case .resume:
            guard suspension.isPaused, suspension.canResume else {
                return
            }
            _ = suspension.remove(.pause)
            if !snapshot.cameraWaiting {
                resumeAfterSuspension()
            }
            if canProgress {
                replayStageCue(
                    timed: snapshot.stage == .instruction || snapshot.stage == .demonstration
                        || snapshot.stage == .feedback)
            }
            snapshot.assistanceKey = nil
        case .stop:
            if stage.isRecordable {
                _ = recordResult(.interrupted)
            }
            progress.finalize(stopped: true, date: Date())
        case .timedPractice:
            guard let configuration = progress.currentActivity,
                configuration.kind == .armRaise || configuration.kind == .elbowBend,
                stage.isRecordable, suspension.isPaused else { return }
            activity = TimedPracticeActivity(configuration: configuration, duration: progress.routine.practiceSeconds)
            snapshot.presentation = activity?.presentation
            enter(.practice(.init()))
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
        #if DEBUG
        case .debugFinish:
            finishActivityForDebug()
        case .debugSkipRest:
            skipRestForDebug()
        #endif
        }
    }

    #if DEBUG
    /// Records the current activity's remaining sets as completed at their goal. The summary block
    /// in `handle` finalizes after the last activity; otherwise an elapsed rest starts the next one.
    private mutating func finishActivityForDebug() {
        if suspension.remove(.pause) {
            endSuspension()
        }

        effects.append(.cancelSpeech)
        gate = nil
        stage.advanceAt = nil
        snapshot.restBreath = nil
        snapshot.assistanceKey = nil

        progress.completeCurrentActivityForDebug(date: Date())

        // Invented sets carry no metrics or key-repetition skeletons.
        recorder = nil
        effects.append(.checkpoint(checkpoint))

        guard progress.summary == nil else {
            return
        }

        // An elapsed rest moves the next tick straight on to the next activity.
        enter(.rest(.init(deadline: now)))
        snapshot.instruction = "session.rest"
        snapshot.seconds = 0
    }

    /// Ends the current rest now. Both rest kinds become an elapsed timed rest, so the tick below
    /// takes the same branch as a rest that ran out: the next set (recalibrating when the set's
    /// feedback asked for it) or the next activity. The breathing narration is cut first, and the
    /// scripted breathing is dropped with the old stage, so none of its steps announce later.
    /// Ignored while paused or waiting for the camera, which only Resume lifts.
    private mutating func skipRestForDebug() {
        guard canProgress, case .rest(let rest) = stage else {
            return
        }

        effects.append(.cancelSpeech)
        snapshot.restBreath = nil

        enter(.rest(.init(
            deadline: now,
            breathing: nil,
            recalibrateBeforeNext: rest.recalibrateBeforeNext
        )))
        tick()
    }
    #endif

    /// True when the current opening or demonstration cue is also a full-page card that must be
    /// read before advancing. The light-layout therapies run these cues over the camera with no
    /// text on screen, so they wait only for their narration.
    private var cueShownOnCard: Bool {
        guard snapshot.stage == .instruction || snapshot.stage == .demonstration else {
            return false
        }

        switch progress.currentActivity?.kind {
        case .armRaise, .elbowBend, .directionalReach, .foldTowel:
            return false
        case .sitToStand, .crossMidline, .externalRotation, .internalRotation, .shoulderFlexion, nil:
            return true
        }
    }

    /// Help text exists only for the dark-layout therapies; the light-layout ones show no Help.
    private var currentAssistanceKey: String? {
        switch progress.currentActivity?.kind {
        case .sitToStand: return "session.assistance.sitToStand"
        case .armRaise, .elbowBend, .directionalReach, .foldTowel,
             .crossMidline, .externalRotation, .internalRotation, .shoulderFlexion, nil:
            return nil
        }
    }

    private mutating func routeActivityCommand(_ command: ActivityCommand) {
        guard case .practice = stage,
            var currentActivity = activity
        else {
            return
        }
        let transition = currentActivity.handle(.command(command, at: now))
        activity = currentActivity
        noteFacts(transition.facts)
        dropCountdownIfAbandoned(transition.presentation)
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

    // MARK: - Suspension and recalibration

    private mutating func pause() {
        _ = suspend(.pause)
    }

    /// Adds a suspension reason and, when it is new, freezes everything that would otherwise run
    /// on: the current repetition, scripted breathing, the activity, and the cue being spoken.
    /// Returns false when the reason was already present.
    private mutating func suspend(_ reason: Suspension.Reason) -> Bool {
        guard suspension.insert(reason, at: now) else {
            return false
        }
        recorder?.discardCurrentRep()
        stage.breathing?.suspend()
        countdown?.stop()
        pendingScriptMovement = nil
        forward(.suspend)
        effects.append(.cancelSpeech)
        gate = nil
        return true
    }

    /// Ends the suspension and lets the activity run again. A countdown that was interrupted waits
    /// for its cue to be spoken again before it restarts.
    private mutating func resumeAfterSuspension() {
        endSuspension()
        forward(.resume)
        snapshot.presentation = activity?.presentation
    }

    /// Speaks the current stage's cue again with a new identity, after a pause or camera wait
    /// cancelled it: the countdown cue when a countdown is pending, otherwise the current line.
    private mutating func replayStageCue(timed: Bool) {
        let speakingCalibration = calibrationCueSpeaking
        let key: String
        if speakingCalibration {
            key = snapshot.instruction
        } else if awaitingCountdownCue {
            key = practiceCountdownKey
        } else {
            key = currentScriptInstruction
        }
        announce(key, timed: timed)
        calibrationCueSpeaking = speakingCalibration
    }

    /// Closes the frozen interval and moves every deadline later by its length, so no stage loses
    /// time to a pause or camera wait. Evidence from before this moment is ignored.
    private mutating func endSuspension() {
        evidenceBoundary = now
        guard let since = suspension.end() else {
            return
        }
        stage.rebase(suspendedAt: since, resumedAt: now)
    }

    private mutating func recalibrate() {
        guard stage.isRecordable else {
            // Cached targets must never survive a camera change while resting between sets.
            stage.requireRecalibrationBeforeNextSet()
            return
        }
        evidenceBoundary = now
        recorder?.discardCurrentRep()
        progress.retryExecution()
        forward(.recalibrate)
        snapshot.presentation = activity?.presentation
        enter(.preparing)
        snapshot.instruction = "session.cameraWait"
        gate = nil
        effects.append(.cancelSpeech)
    }
}
