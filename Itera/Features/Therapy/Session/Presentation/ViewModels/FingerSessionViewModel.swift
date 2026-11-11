//
//  FingerSessionViewModel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Combine
import Observation
import UIKit

@MainActor
@Observable
final class FingerSessionViewModel {
    let sessionLanguage = AppLanguage.selected
    private(set) var sessionElapsedSeconds = 0.0
    @ObservationIgnored private var durationClock = SessionDurationClock()
    @ObservationIgnored private var overlaySmoother = HandOverlaySmoother()
    /// Steadies Vision's left/right reading so a one-frame flip is not treated as the other hand.
    @ObservationIgnored private var sideStabilizer = HandSideStabilizer()
    private(set) var engine: FingerSessionEngine
    private(set) var evidence: HandEvidence?
    private(set) var trackingReady = false
    private(set) var previewAttached = false
    private(set) var waitingForCamera = true
    private(set) var cameraMessage = "camera.position"
    private(set) var errorKey: String?
    private(set) var voiceEnabled = false
    private(set) var voiceNeedsAcknowledgment = false
    private(set) var saving = false
    private(set) var recovering = false
    private(set) var storageNeedsRetry = false
    private(set) var finalSummary: FingerSessionSummary?
    private(set) var finalSummarySaved = false
    var hasFinished: Bool { finalSummary != nil }
    private(set) var hasStarted = false
    private(set) var celebrationID = 0
    private(set) var trackingRecovery = FingerTrackingRecovery()
    private(set) var trackingRecoveryPaused = false
    private(set) var calibrationNeedsHelp = false
    @ObservationIgnored private var instructionSince = 0.0
    @ObservationIgnored private var celebratedSets: [Int: Int] = [:]
    @ObservationIgnored private var lastCountdownCue = ""
    let camera: HandCameraService
    @ObservationIgnored private let audio: GuidanceAudioService
    @ObservationIgnored private let permissions: any PermissionManaging
    @ObservationIgnored private let repository: any FingerSessionRepository
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var timer: AnyCancellable?
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var lastFrame = 0.0
    @ObservationIgnored private var hasPresentedCamera = false
    @ObservationIgnored private var lastHandFrame = 0.0
    private(set) var lastGuideEvidence: HandEvidence?
    private var announcedCalibrationIndex: Int?
    private(set) var practiceCountdownReady = false
    @ObservationIgnored private var spokenFlowKey: String?

    var calibrationMessage: String? {
        switch activity.phase {
        case .baseline, .target, .range:
            return announcedCalibrationIndex == engine.summary.exerciseIndex ? "calibration.try" : "calibration.intro"
        case .rangeResult, .demonstration:
            return "calibration.complete"
        default:
            return nil
        }
    }

    var isCalibrating: Bool { calibrationMessage != nil }

    @ObservationIgnored private var speechID: UUID?
    @ObservationIgnored private var speechDeadline: Double?
    @ObservationIgnored private var previousInstruction = ""
    @ObservationIgnored private var lastRecoverySpoken: String?
    @ObservationIgnored private var previousProgress = -1
    @ObservationIgnored private var previousExercise = 0
    @ObservationIgnored private var wasIdleTimerDisabled = false
    @ObservationIgnored private var language = "id-ID"

    init(routine: FingerRoutine, checkpoint: FingerSessionSummary?, camera: HandCameraService,
         audio: GuidanceAudioService, permissions: any PermissionManaging,
         repository: any FingerSessionRepository) {
        engine = FingerSessionEngine(routine: routine, checkpoint: checkpoint)
        self.camera = camera
        self.audio = audio
        self.permissions = permissions
        self.repository = repository
        celebratedSets[engine.summary.exerciseIndex] = engine.activity.completedSets
    }




    var activity: FingerActivity { engine.activity }
    var paused: Bool { engine.paused }
    var routine: FingerRoutine { engine.summary.routine }
    /// Brief misses retain a drawing anchor only; stale positions are never scored again.
    var guideEvidence: HandEvidence? {
        if trackingReady {
            return lastGuideEvidence
        }
        // A frozen partial hold keeps its bubble at the last drawn position, so the timer
        // visibly pauses instead of disappearing while a bystander passes. Without a hold, a
        // detector dropout shorter than the recovery tolerance keeps the hand drawn, so the
        // overlay does not blink.
        let displayGrace: Double

        if activity.holdCompletionID != nil {
            displayGrace = 0.5
        } else if activity.isHolding {
            displayGrace = InterruptibleHold.trackingGrace
        } else {
            displayGrace = FingerTrackingRecovery.frameTolerance
        }

        guard previewAttached,
              !waitingForCamera,
              ProcessInfo.processInfo.systemUptime - lastHandFrame <= displayGrace else {
            return nil
        }

        return lastGuideEvidence
    }

    var showsGuideIndicators: Bool {
        !paused && guideEvidence != nil && [.baseline, .target, .range, .active].contains(activity.phase)
    }

    var showsGuideTimer: Bool {
        // A frozen hold keeps its paused timer on screen; it receives no time while frozen.
        guard !paused, guideEvidence != nil,
              trackingReady || activity.isHolding else {
            return false
        }
        switch activity.phase {
        case .baseline, .target, .active:
            return true
        case .range:
            // The ready countdown shows its timer; the sweep that follows does not.
            return !activity.rangeReady
        case .rangeResult, .demonstration, .countdown, .feedback, .rest, .finished:
            return false
        }
    }

    var fingerKey: String { "finger." + String(activity.finger) }
    var restBreath: RestBreath? {
        guard activity.phase == .rest, activity.completedSets < routine.sets else {
            return nil
        }
        return RestBreath(elapsed: Double(routine.restSeconds) - activity.remaining)
    }

    var instructionKey: String {
        switch activity.phase {
        case .baseline: return "baseline." + activity.kind.rawValue
        case .target: return "move." + activity.kind.rawValue
        case .range: return activity.rangeReady ? "range.instruction" : "range.ready"
        case .rangeResult: return "calibration.complete"
        case .demonstration: return "calibration.complete"
        case .active: return (activity.returning || activity.needsStart) ? "return." + activity.kind.rawValue : "move." + activity.kind.rawValue
        case .countdown: return "calibration.countdown"
        case .feedback: return "session.good"
        case .rest: return restBreath?.phase.key ?? "session.restInstruction"
        case .finished: return "session.complete"
        }
    }
    var stageKey: String {
        switch activity.phase {
        case .baseline, .target, .range: return "stage.calibration"
        case .rangeResult: return "stage.calibrationResult"
        case .demonstration: return "stage.demonstration"
        case .countdown: return "stage.countdown"
        case .active: return "stage.exercise"
        case .feedback: return "stage.feedback"
        case .rest: return "stage.rest"
        case .finished: return "stage.finished"
        }
    }
    var timeText: String {
        let value = Int(sessionElapsedSeconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    var countdown: Int { max(0, Int(ceil(activity.remaining))) }

    // MARK: - Page presentation

    /// The current exercise's name in the session language, for composed titles.
    var exerciseTitle: String {
        localized(activity.kind.title)
    }

    /// What follows the current rest: another set of this exercise, or the next exercise.
    var upcoming: (exercise: FingerExercise, set: Int)? {
        if activity.completedSets < routine.sets {
            return (activity.kind, activity.completedSets + 1)
        }

        let next = engine.summary.exerciseIndex + 1

        guard routine.exercises.indices.contains(next) else {
            return nil
        }

        return (routine.exercises[next], 1)
    }

    /// The end of a rest previews what comes next, with its demonstration playing.
    var showsUpcomingPreview: Bool {
        guard activity.phase == .rest, upcoming != nil else {
            return false
        }

        let window = min(Self.upcomingPreviewSeconds, Double(routine.restSeconds) / 2)
        return activity.remaining <= window
    }

    /// Length of the "next up" preview at the end of each rest.
    private static let upcomingPreviewSeconds = 5.0

    /// Shortens the current rest; ignored while paused or outside a rest.
    func skipRest() {
        guard !paused, activity.phase == .rest else {
            return
        }

        engine.skipRest()
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: sessionLanguage.resourceBundle)
    }
    var liveFeedbackKey: String {
        guard trackingReady else {
            return cameraMessage
        }
        if activity.phase == .baseline || activity.phase == .target {
            return activity.progress > 0.05 ? "feedback.hold" : "feedback.comfortable"
        }
        if activity.phase == .range {
            guard activity.rangeReady else {
                return activity.holdElapsed > 0.05 ? "feedback.hold" : "feedback.comfortable"
            }
            return activity.rangeTooSmall ? "feedback.rangeTooSmall" : "feedback.rangeMeasuring"
        }
        if activity.phase == .active {
            return activity.progress > 0.75 ? "feedback.almost" : "feedback.slow"
        }
        return instructionKey
    }

    private func updateRewards() {
        guard !paused, !hasFinished else {
            return
        }
        let index = engine.summary.exerciseIndex
        let sets = activity.completedSets
        if sets > celebratedSets[index, default: 0] {
            celebratedSets[index] = sets
            celebrationID += 1
        }
        if activity.phase == .countdown, practiceCountdownReady {
            let cue = "\(index)-\(activity.set)-\(countdown)"
            if cue != lastCountdownCue {
                lastCountdownCue = cue
                // Marizka says "tiga, dua, satu" when recorded; otherwise the beep as before.
                if countdown > 0, !audio.playCount(countdown) {
                    _ = audio.speak(String(countdown))
                }
            }
        }
    }

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        if engine.finished {
            finish(completed: true)
            return
        }
        language = sessionLanguage.speechIdentifier
        subscribe()
        let cameraStatus = await permissions.request(.camera)
        guard !hasFinished else {
            return
        }
        guard cameraStatus == .authorized else {
            errorKey = "camera.permission"
            trackingRecoveryPaused = true
            pause()
            return
        }
        do {
            try audio.configure(language: language)
        } catch {
            errorKey = "audio.unavailable"
        }
        if routine.voiceControl {
            await setVoice(true)
        }
        guard !hasFinished else {
            return
        }
        camera.track(side: routine.side)
        camera.start()
        if !paused {
            audio.startMusic()
            durationClock.resume(at: ProcessInfo.processInfo.systemUptime)
        }
        startTimer()
        await saveCheckpoint()
    }

    private func startTimer() {
        guard timer == nil else {
            return
        }
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick()
        }
    }

    private func subscribe() {
        // Slightly under the 15 Hz inference interval, so throttling never drops a fresh sample.
        camera.events.throttle(for: .milliseconds(60), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] event in self?.receive(event) }.store(in: &subscriptions)
        audio.events.sink { [weak self] event in
            guard let self else {
                return
            }
            switch event {
            case .completed(let id):
                guard id == self.speechID else {
                    return
                }
                self.speechID = nil
                self.speechDeadline = nil
                self.completeNarration()
            case .narrationUnavailable(let id):
                guard id == self.speechID else {
                    return
                }
                self.speechID = nil
                self.speechDeadline = nil
                self.errorKey = "audio.unavailable"
                self.completeNarration()
            case .command(let command):
                self.handleCommand(command)
            case .voiceUnavailable:
                self.voiceEnabled = false
                self.voiceNeedsAcknowledgment = true
                self.errorKey = "voice.unavailable"
                self.pause()
            case .interrupted:
                self.voiceNeedsAcknowledgment = self.voiceEnabled || self.routine.voiceControl
                self.voiceEnabled = false
                self.errorKey = "recovery.interrupted"
                self.pause()
            }
        }.store(in: &subscriptions)
    }

    func holdCompletionPresented(_ id: UUID) {
        guard guideEvidence != nil, !paused, !waitingForCamera else {
            return
        }
        engine.holdCompletionPresented(id)
    }

    func previewReady(_ ready: Bool) { previewAttached = ready }

    private func receive(_ event: HandCameraEvent) {
        guard !hasFinished else {
            return
        }
        switch event {
        case .failure(let key):
            trackingReady = false
            evidence = nil
            lastGuideEvidence = nil
            overlaySmoother.reset()
            sideStabilizer.reset()
            cameraMessage = key
            errorKey = key
            trackingRecoveryPaused = true
            trackingRecovery.missing(.camera, at: ProcessInfo.processInfo.systemUptime)
            engine.recalibrate()
            pause()
        case .sample(let sample):
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sample.timestamp >= 0, now - sample.timestamp <= 0.3 else {
                return
            }
            if generation != sample.generation {
                generation = sample.generation
                lastGuideEvidence = nil
                overlaySmoother.reset()
                sideStabilizer.reset()
                engine.recalibrate()
                announcedCalibrationIndex = nil
                trackingRecovery.reset()
                trackingRecovery.missing(.position, at: now)
                calibrationNeedsHelp = false
                previousInstruction = ""
            }
            lastFrame = sample.timestamp
            if previewAttached && errorKey?.hasPrefix("camera.") == true {
                errorKey = nil
            }
            if !requiresHandTracking && previewAttached {
                trackingRecovery.reset()
            }
            let detected = attributedToExercisedHand(sample.evidence)
            evidence = detected
            guard let hand = detected, hand.side == routine.side,
                  hand.metric(for: activity.kind, finger: activity.finger) != nil else {
                trackingReady = false
                // Keep the drawing filter warm across a brief miss; scoring is suspended immediately.
                if let hand = detected {
                    cameraMessage = hand.side == routine.side ? "camera.showFingers" : "camera.selectedHand"
                } else {
                    cameraMessage = "camera.position"
                }
                let problem: FingerTrackingProblem
                if sample.issue == .multipleHands {
                    problem = .multipleHands
                } else if let hand = detected {
                    problem = hand.side == nil || hand.side == routine.side ? .fingers : .selectedHand
                } else {
                    problem = .position
                }
                if requiresHandTracking {
                    trackingRecovery.missingFrame(problem, at: now)
                }
                handleMissingHand(now: now)
                return
            }
            lastHandFrame = sample.timestamp
            lastGuideEvidence = overlaySmoother.consume(hand)
            let stable: Bool
            if previewAttached {
                stable = trackingRecovery.visible(at: sample.timestamp)
            } else {
                trackingRecovery.missing(.camera, at: now)
                stable = false
            }
            trackingReady = previewAttached && stable
            // Until the reacquired hand is steady, the hold stays frozen rather than reset.
            if !stable {
                engine.suspendEvidence(at: now)
            }
            cameraMessage = "camera.tracking"
            if errorKey?.hasPrefix("camera.") == true {
                errorKey = nil
            }
            if trackingReady, calibrationMessage != "calibration.intro" {
                let previousCompletion = activity.holdCompletionID
                engine.observe(hand, now: now)
                if previousCompletion == nil, activity.holdCompletionID != nil {
                    audio.playCue(.holdCompleted)
                }
            }
            updateRewards()
            updateGuidance()
        }
    }

    /// Forearm rotation turns the palm toward and away from the camera, which makes a hand's
    /// reported chirality unreliable. Capture accepts a single hand, so credit it to the
    /// exercised side instead of rejecting the end of the movement.
    ///
    /// Every other exercise reads the side through `HandSideStabilizer`, which ignores the
    /// brief chirality flips Vision makes while fingers curl or touch.
    private func attributedToExercisedHand(_ hand: HandEvidence?) -> HandEvidence? {
        guard let hand else {
            return nil
        }

        guard activity.kind == .forearmRotation else {
            return sideStabilizer.stabilize(hand)
        }

        return hand.assigning(side: routine.side)
    }

    /// A brief miss (a bystander, an occluded hand) freezes the hold; a long one restarts the cycle.
    private func handleMissingHand(now: Double) {
        if now - lastHandFrame <= InterruptibleHold.trackingGrace {
            engine.suspendEvidence(at: now)
        } else {
            engine.loseEvidence()
        }
    }

    private func tick() {
        guard !hasFinished else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        sessionElapsedSeconds = durationClock.elapsed(at: now)
        if let deadline = speechDeadline, now >= deadline, !paused {
            speechDeadline = nil
            speechID = nil
            audio.cancelSpeech()
            completeNarration()
            errorKey = "audio.unavailable"
        }
        if now - lastFrame > 0.3 {
            trackingReady = false
            evidence = nil
            handleMissingHand(now: now)
            cameraMessage = "camera.position"
        }
        // Demonstrations/countdown require a fresh frame, not a detected patient.
        let frameReady = previewAttached && now - lastFrame <= 0.3
        waitingForCamera = !frameReady
        if frameReady {
            hasPresentedCamera = true
        }
        if !frameReady, speechID != nil {
            speechID = nil
            speechDeadline = nil
            spokenFlowKey = nil
            audio.cancelSpeech()
            previousInstruction = ""
        }
        updateRecovery(now: now, frameReady: frameReady)
        speakRecoveryIfNeeded()
        if activity.phase != .countdown {
            practiceCountdownReady = false
        }
        if activity.phase != .countdown || practiceCountdownReady {
            engine.tick(now, ready: frameReady)
        }
        updateRewards()
        updateGuidance()
        let progress = engine.summary.exerciseIndex * 1000 + activity.totalRepetitions
        if progress != previousProgress {
            previousProgress = progress
            Task { await saveCheckpoint() }
        }
        if engine.finished {
            finish(completed: true)
        }
    }

    private var requiresHandTracking: Bool {
        [.baseline, .target, .active].contains(activity.phase)
    }

    private func updateRecovery(now: Double, frameReady: Bool) {
        guard !paused else {
            return
        }
        if !frameReady {
            trackingRecovery.missing(.camera, at: now)
        } else if !requiresHandTracking {
            trackingRecovery.reset()
        }
        if trackingRecovery.requiresPause(at: now, cameraStartup: !hasPresentedCamera) {
            trackingRecoveryPaused = true
            if trackingRecovery.problem == .camera {
                errorKey = "camera.interrupted"
            }
            pause()
            return
        }
        if activity.phase == .target, trackingReady, instructionSince > 0,
           now - instructionSince >= 15, activity.holdElapsed == 0 {
            calibrationNeedsHelp = true
            if now - instructionSince >= 30 {
                pause()
            }
        }
    }

    var recoveryGuidanceKey: String? {
        if trackingRecovery.showsGuidance(at: ProcessInfo.processInfo.systemUptime) {
            switch trackingRecovery.problem {
            case .position: return "recovery.position"
            case .selectedHand: return routine.side == .left ? "recovery.left" : "recovery.right"
            case .fingers: return "recovery.fingers"
            case .multipleHands: return "recovery.oneHand"
            case .camera: return "recovery.camera"
            case nil: break
            }
        }
        return calibrationNeedsHelp ? "recovery.calibration" : nil
    }

    private func speakRecoveryIfNeeded() {
        guard !paused, calibrationMessage != "calibration.intro",
              calibrationMessage != "calibration.complete", activity.phase != .countdown else {
            return
        }
        guard let key = recoveryGuidanceKey else {
            lastRecoverySpoken = nil
            return
        }
        guard speechID == nil, key != lastRecoverySpoken else {
            return
        }
        lastRecoverySpoken = key
        // Recovery speech is not a progression effect; its completion cannot accept a hold.
        audio.speak(
            String(localized: String.LocalizationValue(key), bundle: sessionLanguage.resourceBundle),
            lines: [NarrationLine(key: key)]
        )
        if trackingRecovery.problem != nil {
            previousInstruction = ""
        }
    }

    private func updateGuidance() {
        guard !paused, previewAttached,
              ProcessInfo.processInfo.systemUptime - lastFrame <= 0.3 else { return }

        let flow = calibrationMessage
        if flow == nil, activity.phase != .countdown,
           trackingRecovery.showsGuidance(at: ProcessInfo.processInfo.systemUptime) {
            return
        }
        if activity.phase == .countdown, practiceCountdownReady {
            return
        }

        let key = (flow ?? instructionKey) + instructionKey
            + (activity.kind.isSequential ? fingerKey : "") + String(engine.summary.exerciseIndex)
        guard key != previousInstruction else {
            return
        }
        previousInstruction = key
        instructionSince = ProcessInfo.processInfo.systemUptime
        calibrationNeedsHelp = false
        narrate()
    }

    private func completeNarration() {
        if spokenFlowKey == "calibration.intro" {
            announcedCalibrationIndex = engine.summary.exerciseIndex
        } else if spokenFlowKey == "calibration.countdown" {
            practiceCountdownReady = true
            lastCountdownCue = ""
        }
        spokenFlowKey = nil
        engine.guidanceCompleted()
    }

    func narrate() {
        guard !paused, !hasFinished else {
            return
        }

        let flow = calibrationMessage
        let key = flow ?? instructionKey
        var lines: [NarrationLine]
        if flow == "calibration.try" {
            lines = [NarrationLine(key: key)] + narrationLines
        } else if flow != nil || activity.phase == .countdown {
            lines = [NarrationLine(key: key)]
        } else {
            lines = narrationLines
        }

        let bundle = sessionLanguage.resourceBundle
        let text = lines.map { line in
            let value = String(localized: String.LocalizationValue(line.key), bundle: bundle)
            if let argument = line.argument {
                return String.localizedStringWithFormat(value, Int64(argument))
            }
            return value
        }.joined(separator: ". ")
        spokenFlowKey = key
        engine.guidanceStarted()
        speechDeadline = ProcessInfo.processInfo.systemUptime + max(15, Double(text.count) * 0.25)
        speechID = audio.speak(text, lines: lines)
    }

    /// The String Catalog keys behind `narrate()`'s text, in the same order, so a bundled
    /// recording of each line can be played instead of the system voice.
    private var narrationLines: [NarrationLine] {
        var lines = [NarrationLine(key: instructionKey)]

        if activity.kind.isSequential && [.baseline, .target, .active].contains(activity.phase) {
            lines.append(NarrationLine(key: fingerKey))
        }

        if narratesHoldDuration {
            lines.append(NarrationLine(key: "guide.holdDuration %lld", argument: Int(activity.holdDuration)))
        }

        return lines
    }

    /// "Tahan 2 detik" closes a hold instruction only when the numbers are not spoken live.
    /// With recorded numbers, "dua, satu" says the same thing, and leaving the line out keeps
    /// the instruction from still playing when the hold, and its first number, begins.
    private var narratesHoldDuration: Bool {
        (activity.phase == .target || activity.phase == .active) && !audio.hasRecordedCounts
    }

    var needsPermissionSettings: Bool {
        errorKey == "camera.permission" || (voiceNeedsAcknowledgment &&
            (permissions.status(for: .microphone) != .authorized ||
             permissions.status(for: .speechRecognition) != .authorized))
    }

    var recoveryPanelKey: String? {
        if storageNeedsRetry || errorKey == "storage.error" {
            return "recovery.storage"
        }
        if errorKey == "camera.permission" {
            return "recovery.cameraPermission"
        }
        if errorKey?.hasPrefix("camera.") == true {
            return "recovery.camera"
        }
        if voiceNeedsAcknowledgment {
            return needsPermissionSettings ? "recovery.voicePermission" : "recovery.voice"
        }
        return errorKey ?? recoveryGuidanceKey
    }

    /// Hand evidence gates movement scoring, while camera readiness gates recovery from a pause.
    var canResume: Bool {
        paused && !hasFinished && !voiceNeedsAcknowledgment && !saving && !recovering && !storageNeedsRetry
            && errorKey != "storage.error"
            && errorKey?.hasPrefix("camera.") != true
            && (!trackingRecoveryPaused || (previewAttached && !waitingForCamera))
    }

    /// Touch and recognized speech enter the same actions and presentation state.
    func handleCommand(_ command: VoiceCommand) {
        switch command {
        case .pause: pause()
        case .resume: resume()
        case .stop: finish()
        case .repeatInstruction: narrate()
        }
    }

    func pause() {
        guard !hasFinished else {
            return
        }
        engine.pause()
        let now = ProcessInfo.processInfo.systemUptime
        durationClock.pause(at: now)
        sessionElapsedSeconds = durationClock.elapsed(at: now)
        speechID = nil
        speechDeadline = nil
        audio.cancelSpeech()
        audio.pauseAmbient()
    }

    func resume() {
        guard canResume else {
            return
        }
        trackingRecoveryPaused = false
        calibrationNeedsHelp = false
        lastRecoverySpoken = nil
        if errorKey == "recovery.interrupted" {
            errorKey = nil
        }
        trackingRecovery.reset()
        if requiresHandTracking && !trackingReady {
            trackingRecovery.missing(.position, at: ProcessInfo.processInfo.systemUptime)
        }
        engine.resume()
        durationClock.resume(at: ProcessInfo.processInfo.systemUptime)
        camera.start()
        audio.resumeAmbient()
        previousInstruction = ""
        updateGuidance()
    }

    func retryCamera() async {
        guard await permissions.request(.camera) == .authorized else {
            errorKey = "camera.permission"
            return
        }
        errorKey = nil
        do {
            try audio.configure(language: language)
        } catch {
            errorKey = "audio.unavailable"
        }
        if (routine.voiceControl || voiceNeedsAcknowledgment) && !voiceEnabled {
            await setVoice(true)
        }
        camera.start()
        if !paused {
            durationClock.resume(at: ProcessInfo.processInfo.systemUptime)
        }
        startTimer()
    }

    func retryRecovery() async {
        guard !recovering, !saving else {
            return
        }
        recovering = true
        defer { recovering = false }
        if storageNeedsRetry || errorKey == "storage.error" {
            await saveCheckpoint()
        } else if errorKey?.hasPrefix("camera.") == true {
            await retryCamera()
        } else if voiceNeedsAcknowledgment || errorKey == "voice.unavailable" {
            await setVoice(true)
        } else if calibrationNeedsHelp {
            retryCalibration()
        } else {
            await retryCamera()
        }
    }

    func skipCurrent() {
        guard paused else {
            return
        }
        engine.skipCurrent()
        calibrationNeedsHelp = false
        trackingRecoveryPaused = false
        trackingRecovery.reset()
        previousInstruction = ""
        if engine.finished {
            finish(completed: true)
        }
        else { Task { await saveCheckpoint() } }
    }

    func remeasureRange() {
        engine.remeasureRange()
        previousInstruction = ""
        updateGuidance()
    }

    func retryCalibration() {
        announcedCalibrationIndex = nil
        calibrationNeedsHelp = false
        trackingRecoveryPaused = false
        trackingRecovery.reset()
        engine.recalibrate()
        previousInstruction = ""
        if !paused {
            updateRewards()
            updateGuidance()
        }
    }

    func setVoice(_ enabled: Bool) async {
        if !enabled {
            audio.disableVoice()
            voiceEnabled = false
            return
        }
        let microphone = await permissions.request(.microphone)
        guard !hasFinished else {
            return
        }
        let speech = await permissions.request(.speechRecognition)
        guard !hasFinished else {
            return
        }
        guard microphone == .authorized, speech == .authorized else {
            errorKey = "voice.unavailable"
            voiceNeedsAcknowledgment = true
            pause()
            return
        }
        do {
            try audio.configure(language: language)
            voiceEnabled = try audio.enableVoice()
        } catch {
            voiceEnabled = false
        }
        if !voiceEnabled {
            voiceNeedsAcknowledgment = true
            errorKey = "voice.unavailable"
            pause()
        } else {
            voiceNeedsAcknowledgment = false
            if errorKey == "voice.unavailable" {
                errorKey = nil
            }
        }
    }


    func background() {
        guard hasStarted, !hasFinished else {
            return
        }
        voiceNeedsAcknowledgment = voiceEnabled || routine.voiceControl
        trackingRecoveryPaused = true
        waitingForCamera = true
        pause()
        camera.stop()
        audio.suspend()
        voiceEnabled = false
        trackingReady = false
        Task { await saveCheckpoint() }
    }

    func foreground() {
        guard hasStarted, !hasFinished else {
            return
        }
        permissions.refresh()
        guard permissions.status(for: .camera) == .authorized else {
            errorKey = "camera.permission"
            return
        }
        camera.start()
        startTimer()
    }

    func finish(completed: Bool = false) {
        guard !hasFinished else {
            return
        }
        errorKey = nil
        finalSummary = engine.snapshot(outcome: completed ? .completed : .stopped)
        cleanup()
    }

    func saveForLater() async -> Bool {
        guard !saving else {
            return false
        }
        pause()
        saving = true
        defer { saving = false }
        let snapshot = engine.snapshot(outcome: .savedForLater)
        do {
            try await repository.checkpoint(snapshot)
            storageNeedsRetry = false
            cleanup()
            return true
        } catch {
            storageNeedsRetry = true
            errorKey = "storage.error"
            return false
        }
    }

    func saveFinalSummary() async {
        guard !saving, !finalSummarySaved, let summary = finalSummary else {
            return
        }

        saving = true
        defer { saving = false }

        do {
            try await repository.finalize(summary)
            storageNeedsRetry = false
            errorKey = nil
            finalSummarySaved = true
        } catch {
            storageNeedsRetry = true
            errorKey = "storage.error"
        }
    }

    func saveCheckpoint() async {
        guard hasStarted, !hasFinished else {
            return
        }
        let snapshot = engine.snapshot(outcome: .interrupted)
        do {
            try await repository.checkpoint(snapshot)
            guard !hasFinished else {
                return
            }
            storageNeedsRetry = false
            if errorKey == "storage.error" {
                errorKey = nil
            }
        } catch {
            guard !hasFinished else {
                return
            }
            storageNeedsRetry = true
            errorKey = "storage.error"
            pause()
        }
    }

    func cleanup() {
        hasStarted = false
        let now = ProcessInfo.processInfo.systemUptime
        durationClock.pause(at: now)
        sessionElapsedSeconds = durationClock.elapsed(at: now)
        overlaySmoother.reset()
        lastGuideEvidence = nil
        evidence = nil
        trackingReady = false
        timer?.cancel()
        timer = nil
        subscriptions.removeAll()
        camera.stop()
        audio.stop()
        UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
    }
}
