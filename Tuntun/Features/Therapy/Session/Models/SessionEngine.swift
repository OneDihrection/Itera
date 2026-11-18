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
    case cancelSpeech
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
    var assistanceKey: String?
    var cameraWaiting = true
    var summary: SessionSummary?
    /// Every set recorded so far, so set pages can show earlier sets before the summary exists.
    var results: [SessionActivityResult] = []
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
    /// Limits live towel speech to the first cue and a stuck reminder.
    private var towelSpeech = TowelSpeechPolicy()
    private var awaitingCountdownGuidance = false
    private var calibrationCompletionPending = false
    private var announcedCountdown: Int?
    /// Per-repetition metrics and key-repetition skeletons for the current set.
    private var recorder: KeyRepRecorder?
    /// When a stale-frame rejection was last logged, so the log stays at most one line every 3 s.
    private var lastStaleLog = -Double.infinity

    /// How long the session keeps guidance running without a scoring-fresh frame before it waits
    /// for the camera. Scoring still rejects frames older than 300 ms; this only stops a brief
    /// inference or main-thread hitch from cancelling narration and replaying it on every gap.
    static let cameraWaitGrace = 1.0

    init(routine: Routine = .demo(), date: Date = Date(), scriptedArmRaise: Bool = false) {
        self.scriptedArmRaise = scriptedArmRaise
        progress = SessionProgress(routine: routine, startedAt: date)
        selectActivity()
    }

    // MARK: - Events

    mutating func handle(_ event: SessionEvent, at time: Double) -> SessionTransition {
        let previousCountdown = snapshot.presentation?.countdownSeconds
        effects = []
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
           snapshot.presentation?.countdownSeconds != nil,
           previousCountdown == nil, !awaitingCountdownGuidance {
            announcePracticeCountdown()
        }
        if canProgress {
            let seconds = snapshot.stage == .activity && !awaitingCountdownGuidance
                ? snapshot.presentation?.countdownSeconds : nil
            if let seconds, seconds > 0, seconds != announcedCountdown {
                effects.append(.audio(UUID(), .countdown(seconds)))
            }
            announcedCountdown = seconds
        }
        snapshot.guidanceID = gate?.id
        snapshot.countdownRunning = countdownClockRunning
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

    private var isCalibrationCompletionCue: Bool {
        snapshot.instruction == "calibration.complete" || snapshot.instruction == snapshot.armRaiseNarrationPrefix + "calibration.complete"
    }

    private var practiceCountdownKey: String {
        guard snapshot.usesArmRaiseScript else {
            return "calibration.countdown"
        }
        return progress.setNumber == 1 ? snapshot.armRaiseNarrationPrefix + "countdown.first" : snapshot.armRaiseNarrationPrefix + "countdown.next"
    }

    private var currentScriptInstruction: String {
        if snapshot.usesArmRaiseScript, snapshot.stage == .activity,
           !isCalibrationCompletionCue, case .movement(let movement) = activity?.presentation {
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

    private mutating func selectActivity() {
        calibrationCompletionPending = false
        awaitingCountdownGuidance = false
        announcedCountdown = nil
        guard let configuration = progress.currentActivity else {
            return
        }
        snapshot.usesArmRaiseScript = scriptedArmRaise && ArmRaiseGuidance.applies(to: configuration)
        snapshot.armRaiseScriptSide = configuration.side
        pendingScriptMovement = nil
        lastScriptHoldCount = ""
        recorder = KeyRepRecorder(activity: configuration)
        switch configuration.kind {
        case .foldTowel: activity = FoldTowelActivity(configuration: configuration)
        case .armRaise:
            activity = ArmRaiseActivity(configuration: configuration, scriptedGuidance: snapshot.usesArmRaiseScript)
        case .elbowBend: activity = ElbowBendActivity(configuration: configuration)
        case .directionalReach: activity = DirectionalReachActivity(configuration: configuration)
        case .sitToStand, .crossMidline, .externalRotation, .internalRotation, .shoulderFlexion:
            // Balancing exercises run on their own screens. Sit-to-stand stays only so routines
            // saved before Trunk Control moved there still decode; nothing offers it any more.
            activity = nil
        }
        if let viewport { _ = activity?.handle(.viewport(viewport)) }
        evidenceBoundary = now
        snapshot.activity = configuration
        snapshot.presentation = activity?.presentation
        enter(.preparing)
        snapshot.guidedSetBreathing = nil
        snapshot.instruction = "session.cameraWait"
        gate = nil
    }

    /// The only place the stage changes. The cue being spoken is left alone: it belongs to the
    /// narration, and the next `announce` replaces it.
    private mutating func enter(_ next: SessionStage) {
        stage = next
        snapshot.stage = next.presentation
    }

    private mutating func beginNextSet(recalibrating: Bool) {
        _ = activity?.handle(.resume)
        _ = activity?.handle(.nextSet)
        if recalibrating {
            _ = activity?.handle(.recalibrate)
            snapshot.presentation = activity?.presentation
            enter(.preparing)
            gate = nil
            updateReadiness()
            return
        }
        snapshot.presentation = activity?.presentation
        enter(.practice)
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
            NSLog("Session frame rejected as stale age=%.3f", now - frame.timestamp)
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
        guard canProgress, snapshot.stage == .activity, frame.timestamp >= evidenceBoundary else {
            return
        }
        guard !awaitingCountdownGuidance else { return }
        let old = activity?.presentation
        let previousInstruction = snapshot.instruction
        guard let result = activity?.handle(.observation(frame)) else {
            return
        }
        snapshot.presentation = result.presentation
        snapshot.instruction = result.presentation.instruction
        if let clip = recorder?.observe(frame, presentation: result.presentation) {
            effects.append(.keepRepClip(clip))
        }
        if result.status == .finished {
            record(.completed)
            if case .towel = result.presentation {
                effects.append(.audio(UUID(), .towelCompleted))
            }
            return
        }
        if case .towel(let before) = old, case .towel(let after) = result.presentation {
            // Live towel speech is limited by `towelSpeech` and runs from the tick, never from here.
            if after.count != before.count {
                effects.append(.audio(UUID(), .towelCompleted))
            } else if after.foldIndex != before.foldIndex {
                effects.append(.audio(UUID(), .towelFold))
            } else if after.grabID != before.grabID {
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
                if old?.countdownSeconds == nil {
                    announcePracticeCountdown()
                }
            } else if old?.count != after.count {
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
        if case .movement(let before) = old, case .movement(let after) = result.presentation,
            before.phase != after.phase {
            if after.phase == .targetCapture {
                enter(.opening(.init(step: .tryMovement)))
                snapshot.seconds = 0
                announce("calibration.try", timed: false)
                return
            }
            if after.phase == .returnToStart, before.phase == .targetCapture {
                pendingPrefix = .target
                announce(result.presentation.instruction, timed: false)
                return
            }
        }
        if result.presentation.countdownSeconds != nil {
            if old?.countdownSeconds == nil {
                announcePracticeCountdown()
            }
        } else if case .movement = result.presentation, old?.count != result.presentation.count {
            // Each accepted repetition is counted aloud.
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
            _ = activity?.handle(.resume)
            if let configuration = progress.currentActivity {
                let plan = SessionGuidance.opening(configuration, includePositioning: positioningPending)
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
        if snapshot.stage == .activity && !awaitingCountdownGuidance {
            let previous = snapshot.presentation
            _ = activity?.handle(.tick(now))
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
                if case .towel(let before) = previous,
                   before.phase == .countdown, after.phase == .practice {
                    evidenceBoundary = now
                }
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
            } else if step != breathing.step {
                announce(snapshot.armRaiseNarrationPrefix + breathing.key, timed: false)
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
                effects.append(.cancelSpeech)
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
            breathing = BreathingRest(opensAfterFirstSet: progress.setNumber == 1)
        } else {
            breathing = nil
        }

        enter(.rest(.init(
            deadline: breathing == nil ? now + max(0, progress.routine.restSeconds) : nil,
            breathing: breathing,
            recalibrateBeforeNext: feedback.recalibrateBeforeNext
        )))
        snapshot.instruction = "session.rest"

        if let breathing {
            announce(snapshot.armRaiseNarrationPrefix + breathing.key, timed: false)
        } else if !progress.hasNextSet {
            announce("session.rest", timed: false)
        }
    }

    /// Preparation starts its deadline when its narration ends, and an activity countdown starts
    /// when `countdownReady` is sent (`awaitingCountdownGuidance` covers the wait, including after a
    /// resume). Rest has no wait.
    private var countdownClockRunning: Bool {
        switch snapshot.stage {
        case .preparationWait:
            return stage.advanceAt != nil
        case .activity:
            return snapshot.presentation?.countdownSeconds != nil && !awaitingCountdownGuidance
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
            && snapshot.presentation?.countdownSeconds == nil
        if timed || liveTowel || snapshot.usesArmRaiseScript {
            effects.append(.cancelSpeech)
        }
        let id = UUID()
        gate = GuidanceGate(
            id: id,
            startedAt: now,
            watchdog: watchdogSeconds(timed: timed),
            read: snapshot.stage != .instruction && snapshot.stage != .demonstration
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

    private mutating func announcePracticeCountdown() {
        awaitingCountdownGuidance = true
        announcedCountdown = nil
        if calibrationCompletionPending {
            calibrationCompletionPending = false
            announce(snapshot.usesArmRaiseScript ? snapshot.armRaiseNarrationPrefix + "calibration.complete" : "calibration.complete", timed: false)
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
                    enter(.practice)
                    evidenceBoundary = now
                    _ = activity?.handle(.guidanceCompleted(now))
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
                beginCards(.opening(configuration, includePositioning: positioningPending))
                return
            }
            stage.advanceAt = now
        }
        if snapshot.stage == .activity {
            // A live towel cue may finish late, fail, or never finish. None changes mechanics.
            if case .towel(let towel) = snapshot.presentation, towel.phase == .practice {
                return
            }
            if awaitingCountdownGuidance {
                if snapshot.instruction == "calibration.complete" || snapshot.instruction == snapshot.armRaiseNarrationPrefix + "calibration.complete" {
                    announce(practiceCountdownKey, timed: false)
                    return
                }
                awaitingCountdownGuidance = false
                _ = activity?.handle(.countdownReady(now))
                snapshot.presentation = activity?.presentation
            }
            _ = activity?.handle(.guidanceCompleted(now))
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
            stage.advanceAt = demonstration ? now + 8 : now + (guidancePlan?.quietDelay ?? 3)
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
        enter(.practice)
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
            enter(.practice)
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
    #endif

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
        guard stage == .practice,
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

    // MARK: - Suspension and recalibration

    private mutating func pause() {
        guard suspend(.pause) else {
            return
        }
        announcedCountdown = nil
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
        pendingScriptMovement = nil
        _ = activity?.handle(.suspend)
        effects.append(.cancelSpeech)
        gate = nil
        return true
    }

    /// Ends the suspension and lets the activity run again. A countdown that was interrupted waits
    /// for its cue to be spoken again before it restarts.
    private mutating func resumeAfterSuspension() {
        endSuspension()
        _ = activity?.handle(.resume)
        snapshot.presentation = activity?.presentation
        awaitingCountdownGuidance = snapshot.presentation?.countdownSeconds != nil
    }

    /// Speaks the current stage's cue again with a new identity, after a pause or camera wait
    /// cancelled it: the countdown cue when a countdown is pending, otherwise the current line.
    private mutating func replayStageCue(timed: Bool) {
        let key = awaitingCountdownGuidance && !isCalibrationCompletionCue
            ? practiceCountdownKey
            : currentScriptInstruction
        announce(key, timed: timed)
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
        awaitingCountdownGuidance = false
        announcedCountdown = nil
        evidenceBoundary = now
        recorder?.discardCurrentRep()
        progress.retryExecution()
        _ = activity?.handle(.recalibrate)
        snapshot.presentation = activity?.presentation
        enter(.preparing)
        snapshot.instruction = "session.cameraWait"
        gate = nil
        effects.append(.cancelSpeech)
    }
}
