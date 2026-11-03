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
    private(set) var sessionElapsedSeconds = 0.0
    @ObservationIgnored private var durationClock = SessionDurationClock()
    @ObservationIgnored private var overlaySmoother = HandOverlaySmoother()
    private(set) var engine: FingerSessionEngine
    private(set) var evidence: HandEvidence?
    private(set) var trackingReady = false
    private(set) var previewAttached = false
    private(set) var waitingForCamera = true
    private(set) var cameraMessage = "camera.position"
    private(set) var errorKey: String?
    private(set) var voiceEnabled = false
    private(set) var voiceNeedsAcknowledgment = false
    private(set) var needsReflection = false
    private(set) var saving = false
    private(set) var finalSummary: FingerSessionSummary?
    private(set) var hasStarted = false
    private(set) var celebrationID = 0
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
    @ObservationIgnored private var lastHandFrame = 0.0
    private var lastGuideEvidence: HandEvidence?
    @ObservationIgnored private var speechID: UUID?
    @ObservationIgnored private var speechDeadline: Double?
    @ObservationIgnored private var previousInstruction = ""
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
    /// Completed cues may use their last accepted anchor briefly; it is never scored again.
    var guideEvidence: HandEvidence? {
        if trackingReady {
            return lastGuideEvidence
        }
        guard activity.holdCompletionID != nil, previewAttached, !waitingForCamera,
              ProcessInfo.processInfo.systemUptime - lastHandFrame <= 0.5 else {
            return nil
        }
        return lastGuideEvidence
    }

    var showsGuideTimer: Bool {
        guard !paused, guideEvidence != nil else {
            return false
        }
        switch activity.phase {
        case .baseline, .target, .active:
            return true
        case .range, .rangeResult, .demonstration, .countdown, .feedback, .rest, .finished:
            return false
        }
    }

    var fingerKey: String { "finger." + String(activity.finger) }
    var instructionKey: String {
        switch activity.phase {
        case .baseline: return "baseline." + activity.kind.rawValue
        case .target: return "move." + activity.kind.rawValue
        case .range: return "range.instruction"
        case .rangeResult: return "range.resultSpoken"
        case .demonstration: return "demo." + activity.kind.rawValue
        case .active: return (activity.returning || activity.needsStart) ? "return." + activity.kind.rawValue : "move." + activity.kind.rawValue
        case .countdown: return "session.ready"
        case .feedback: return "session.good"
        case .rest: return "session.restInstruction"
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
    var demonstrationTimeText: String {
        let seconds = max(0, Int(ceil(activity.demonstrationRemaining)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var countdown: Int { max(0, Int(ceil(activity.remaining))) }
    var liveFeedbackKey: String {
        guard trackingReady else {
            return cameraMessage
        }
        if activity.phase == .baseline || activity.phase == .target {
            return activity.progress > 0.05 ? "feedback.hold" : "feedback.comfortable"
        }
        if activity.phase == .range {
            return activity.rangeTooSmall ? "feedback.rangeTooSmall" : "feedback.rangeMeasuring"
        }
        if activity.phase == .active {
            return activity.progress > 0.75 ? "feedback.almost" : "feedback.slow"
        }
        return instructionKey
    }

    func readReflection() {
        do {
            try audio.configure(language: language, ambientSound: false)
            audio.speak(String(localized: "reflection.title"))
        } catch {
            errorKey = "audio.unavailable"
        }
    }

    private func updateRewards() {
        guard !paused, !needsReflection else {
            return
        }
        let index = engine.summary.exerciseIndex
        let sets = activity.completedSets
        if sets > celebratedSets[index, default: 0] {
            celebratedSets[index] = sets
            celebrationID += 1
            audio.playCue(.setCompleted)
        }
        if activity.phase == .countdown, !paused {
            let cue = "\(index)-\(activity.set)-\(countdown)"
            if cue != lastCountdownCue {
                lastCountdownCue = cue
                audio.playCue(.countdown)
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
        language = Locale.current.language.languageCode?.identifier == "id" ? "id-ID" : "en-US"
        subscribe()
        let cameraStatus = await permissions.request(.camera)
        guard !needsReflection else {
            return
        }
        guard cameraStatus == .authorized else {
            errorKey = "camera.permission"
            return
        }
        do {
            try audio.configure(language: language, ambientSound: routine.ambientSound)
        } catch {
            errorKey = "audio.unavailable"
        }
        if routine.voiceControl {
            await setVoice(true)
        }
        guard !needsReflection else {
            return
        }
        camera.start()
        if !paused {
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
        camera.events.throttle(for: .milliseconds(70), scheduler: DispatchQueue.main, latest: true)
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
                self.engine.guidanceCompleted()
            case .narrationUnavailable(let id):
                guard id == self.speechID else {
                    return
                }
                self.speechID = nil
                self.speechDeadline = nil
                self.errorKey = "audio.unavailable"
                self.engine.guidanceCompleted()
            case .command(let command):
                self.handleCommand(command)
            case .voiceUnavailable:
                self.voiceEnabled = false
                self.voiceNeedsAcknowledgment = true
                self.pause()
            case .interrupted:
                self.voiceEnabled = false
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
        guard !needsReflection else {
            return
        }
        switch event {
        case .failure(let key):
            trackingReady = false
            evidence = nil
            lastGuideEvidence = nil
            overlaySmoother.reset()
            cameraMessage = key
            errorKey = key
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
                engine.recalibrate()
                previousInstruction = ""
            }
            lastFrame = sample.timestamp
            let detected = attributedToExercisedHand(sample.evidence)
            evidence = detected
            guard let hand = detected, hand.side == routine.side,
                  hand.metric(for: activity.kind, finger: activity.finger) != nil else {
                trackingReady = false
                overlaySmoother.reset()
                if let hand = detected {
                    cameraMessage = hand.side == routine.side ? "camera.showFingers" : "camera.selectedHand"
                } else {
                    cameraMessage = "camera.position"
                }
                handleMissingHand(now: now)
                return
            }
            lastHandFrame = sample.timestamp
            lastGuideEvidence = overlaySmoother.consume(hand)
            trackingReady = previewAttached
            cameraMessage = "camera.tracking"
            if errorKey?.hasPrefix("camera.") == true {
                errorKey = nil
            }
            if trackingReady {
                engine.observe(hand, now: now)
            }
            updateRewards()
            updateGuidance()
        }
    }

    /// Forearm rotation turns the palm toward and away from the camera, which makes a hand's
    /// reported chirality unreliable. Capture accepts a single hand, so credit it to the
    /// exercised side instead of rejecting the end of the movement.
    private func attributedToExercisedHand(_ hand: HandEvidence?) -> HandEvidence? {
        guard activity.kind == .forearmRotation, let hand else {
            return hand
        }
        return hand.assigning(side: routine.side)
    }

    private func handleMissingHand(now: Double) {
        if now - lastHandFrame <= 0.5 {
            engine.suspendEvidence()
        } else {
            engine.loseEvidence()
        }
    }

    private func tick() {
        guard !needsReflection else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        sessionElapsedSeconds = durationClock.elapsed(at: now)
        if let deadline = speechDeadline, now >= deadline, !paused {
            speechDeadline = nil
            speechID = nil
            audio.cancelSpeech()
            engine.guidanceCompleted()
            errorKey = "audio.unavailable"
        }
        if now - lastFrame > 0.3 {
            trackingReady = false
            evidence = nil
            overlaySmoother.reset()
            handleMissingHand(now: now)
            cameraMessage = "camera.position"
        }
        // Demonstrations/countdown require a fresh frame, not a detected patient.
        let frameReady = previewAttached && now - lastFrame <= 0.3
        waitingForCamera = !frameReady
        if !frameReady, speechID != nil {
            speechID = nil
            speechDeadline = nil
            audio.cancelSpeech()
            previousInstruction = ""
        }
        engine.tick(now, ready: frameReady)
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

    private func updateGuidance() {
        guard !paused, previewAttached,
              ProcessInfo.processInfo.systemUptime - lastFrame <= 0.3 else { return }
        let key = instructionKey + (activity.kind.isSequential ? fingerKey : "") + String(engine.summary.exerciseIndex)
        guard key != previousInstruction else {
            return
        }
        previousInstruction = key
        narrate()
    }

    func narrate() {
        guard !paused, !needsReflection else {
            return
        }
        var text = String(localized: String.LocalizationValue(instructionKey))
        if activity.kind.isSequential && [.baseline, .target, .active].contains(activity.phase) {
            text += ". " + String(localized: String.LocalizationValue(fingerKey))
        }
        if activity.phase == .target || activity.phase == .active {
            text += ". " + String.localizedStringWithFormat(
                String(localized: "guide.holdDuration %lld"), Int64(activity.holdDuration)
            )
        }
        engine.guidanceStarted()
        speechDeadline = ProcessInfo.processInfo.systemUptime + max(15, Double(text.count) * 0.25)
        speechID = audio.speak(text)
    }

    var canResume: Bool {
        paused && !needsReflection && !voiceNeedsAcknowledgment && !saving && errorKey != "storage.error"
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
        guard !needsReflection else {
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
        engine.resume()
        durationClock.resume(at: ProcessInfo.processInfo.systemUptime)
        camera.start()
        audio.resumeAmbient()
        previousInstruction = ""
        updateGuidance()
    }

    func retryCamera() async {
        if await permissions.request(.camera) == .authorized {
            errorKey = nil
            camera.start()
            if !paused {
                durationClock.resume(at: ProcessInfo.processInfo.systemUptime)
            }
            startTimer()
        }
    }

    func skipCurrent() {
        guard paused else {
            return
        }
        engine.skipCurrent()
        previousInstruction = ""
        if engine.finished {
            finish(completed: true)
        }
        else { Task { await saveCheckpoint() } }
    }

    func confirmRange() {
        engine.confirmRange()
        previousInstruction = ""
        updateGuidance()
    }

    func remeasureRange() {
        engine.remeasureRange()
        previousInstruction = ""
        updateGuidance()
    }

    func retryCalibration() {
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
        guard !needsReflection else {
            return
        }
        let speech = await permissions.request(.speechRecognition)
        guard !needsReflection else {
            return
        }
        guard microphone == .authorized, speech == .authorized else {
            voiceNeedsAcknowledgment = true
            pause()
            return
        }
        do {
            voiceEnabled = try audio.enableVoice()
        } catch {
            voiceEnabled = false
        }
        if !voiceEnabled {
            voiceNeedsAcknowledgment = true
            pause()
        }
    }

    func acknowledgeTouch() { voiceNeedsAcknowledgment = false }

    func background() {
        guard hasStarted, !needsReflection else {
            return
        }
        pause()
        camera.stop()
        audio.suspend()
        voiceEnabled = false
        trackingReady = false
        Task { await saveCheckpoint() }
    }

    func foreground() {
        guard hasStarted, !needsReflection else {
            return
        }
        camera.start()
    }

    func finish(completed: Bool = false) {
        guard !needsReflection else {
            return
        }
        errorKey = nil
        finalSummary = engine.snapshot(outcome: completed ? .completed : .stopped)
        needsReflection = true
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
            cleanup()
            return true
        } catch {
            errorKey = "storage.error"
            return false
        }
    }

    func recordFeeling(_ feeling: SessionFeeling) async -> FingerSessionSummary? {
        guard !saving, var summary = finalSummary else {
            return nil
        }
        saving = true
        defer { saving = false }
        summary.feeling = feeling
        do {
            try await repository.finalize(summary)
            finalSummary = summary
            audio.stop()
            return summary
        } catch {
            errorKey = "storage.error"
            return nil
        }
    }

    func saveCheckpoint() async {
        guard hasStarted, !needsReflection else {
            return
        }
        let snapshot = engine.snapshot(outcome: .interrupted)
        do {
            try await repository.checkpoint(snapshot)
            if errorKey == "storage.error" {
                errorKey = nil
            }
        } catch {
            errorKey = "storage.error"
            pause()
        }
    }

    func cleanup() {
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
