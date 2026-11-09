//
//  BalanceSessionViewModel.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import Combine
import Observation
import UIKit

@MainActor
@Observable
final class BalanceSessionViewModel {
    private(set) var snapshot = BalanceSnapshot()
    private(set) var permissionDenied = false
    private(set) var cameraWaiting = true
    private(set) var failure: String?
    private(set) var frontCamera = true
    private(set) var paused = false
    private(set) var voiceListening = false
    private(set) var voiceAvailable = true
    private(set) var requestedExit = false
    let holdSeconds: Int
    let exercise: BalanceExercise

    // MARK: Sets

    /// The set being practiced, from 1.
    private(set) var setNumber = 1
    let totalSets: Int
    let restSeconds: Int
    /// Repetitions of every finished set, in order.
    private(set) var setResults: [Int] = []
    /// Seconds left before the next set while resting between sets, otherwise `nil`.
    private(set) var restRemaining: Int?

    /// True once the last set is finished.
    var allSetsDone: Bool {
        setResults.count >= totalSets
    }

    @ObservationIgnored let tracking: BodyTrackingService
    @ObservationIgnored private let audio: SessionAudioService
    @ObservationIgnored private var engine: any BalanceMovementEngine
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var landscapeRight = false
    @ObservationIgnored private var wasIdleTimerDisabled = false
    @ObservationIgnored private var lastSpokenCountdown: Int?
    /// The calibration pose already explained aloud, so each is spoken once per calibration.
    @ObservationIgnored private var spokenCalibrationKey: String?
    /// Practice time shown on the pause dialog; explicit pauses do not count.
    @ObservationIgnored private var clock = SessionDurationClock()
    @ObservationIgnored private var restTask: Task<Void, Never>?

    init(
        tracking: BodyTrackingService,
        audio: SessionAudioService,
        settings: BalancePracticeSettings,
        exercise: BalanceExercise = .crossMidline
    ) {
        let repetitions = settings.repetitions
        let holdSeconds = settings.holdSeconds
        let armSelection = settings.armSelection

        self.tracking = tracking
        self.audio = audio
        self.holdSeconds = min(20, max(3, holdSeconds))
        self.exercise = exercise
        totalSets = settings.sets
        restSeconds = settings.restSeconds
        switch exercise {
        case .crossMidline:
            engine = CrossMidlineBalanceEngine(
                goal: repetitions,
                holdDuration: Double(holdSeconds),
                armSelection: armSelection
            )
        case .sitToStand:
            engine = SitToStandBalanceEngine(goal: repetitions)
        case .externalRotation, .internalRotation, .shoulderFlexion:
            engine = ArmMovementEngine(
                goal: repetitions,
                holdDuration: Double(holdSeconds),
                armSelection: armSelection,
                exercise: exercise
            )
        }
        snapshot = engine.snapshot
    }

    func start(permissions: any PermissionManaging) async {
        guard !started else { return }
        let status = await permissions.request(.camera)
        guard status == .authorized else {
            permissionDenied = true
            return
        }

        permissionDenied = false
        started = true
        wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        tracking.requireCup(false)

        tracking.frames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }
                let previous = self.snapshot
                self.engine.consume(frame, scoringEnabled: !self.paused)
                self.snapshot = self.engine.snapshot
                self.updateAudio(from: previous, to: self.snapshot)
                if previous.phase != .complete, self.snapshot.phase == .complete {
                    self.finishSet()
                }
            }
            .store(in: &subscriptions)

        tracking.availability
            .receive(on: DispatchQueue.main)
            .sink { [weak self] availability in
                guard let self else { return }
                switch availability {
                case .ready:
                    self.cameraWaiting = false
                case .waiting:
                    self.cameraWaiting = true
                case .discontinuity:
                    self.cameraWaiting = true
                    self.engine.invalidateCalibration()
                    self.snapshot = self.engine.snapshot
                }
            }
            .store(in: &subscriptions)

        tracking.failures
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.failure = error
                self?.cameraWaiting = true
            }
            .store(in: &subscriptions)

        audio.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &subscriptions)

        tracking.start()
        clock.resume(at: Self.now)
        audio.prepare()
        let microphone = await permissions.request(.microphone)
        let speech = await permissions.request(.speechRecognition)
        if microphone == .authorized, speech == .authorized {
            startVoiceListening()
        } else {
            voiceAvailable = false
        }
        if !paused, !allSetsDone {
            audio.startMusic()
        }
    }

    // MARK: - Sets and rest

    /// Practice time so far, for the pause dialog.
    var elapsedSeconds: Int {
        Int(clock.elapsed(at: Self.now))
    }

    private static var now: Double {
        ProcessInfo.processInfo.systemUptime
    }

    /// Records the finished set, then rests before the next one, or ends after the last.
    private func finishSet() {
        setResults.append(snapshot.metrics.completedTouches)

        guard !allSetsDone else {
            clock.pause(at: Self.now)
            tracking.stop()
            audio.stopMusic()
            return
        }

        restRemaining = restSeconds
        restTask?.cancel()
        restTask = Task { [weak self] in
            await self?.runRest()
        }
    }

    /// Counts the rest down once a second; a pause freezes it.
    private func runRest() async {
        while let remaining = restRemaining, remaining > 0 {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            guard !paused else {
                continue
            }

            restRemaining = remaining - 1
        }

        startNextSet()
    }

    /// Keeps the calibration: the patient starts the next set from the usual return to start.
    private func startNextSet() {
        guard restRemaining != nil, !allSetsDone else {
            return
        }

        restRemaining = nil
        setNumber += 1
        lastSpokenCountdown = nil
        engine.nextSet()
        snapshot = engine.snapshot
    }

    func previewReady(_ ready: Bool) {
        if ready { cameraWaiting = false }
    }

    func orientationChanged(right: Bool) {
        landscapeRight = right
        tracking.configure(front: frontCamera, landscapeRight: right)
    }

    func switchCamera() {
        frontCamera.toggle()
        cameraWaiting = true
        engine.invalidateCalibration()
        snapshot = engine.snapshot
        tracking.configure(front: frontCamera, landscapeRight: landscapeRight)
    }

    func restart() {
        restTask?.cancel()
        restTask = nil
        restRemaining = nil
        setNumber = 1
        setResults = []
        clock = SessionDurationClock()
        clock.resume(at: Self.now)
        paused = false
        requestedExit = false
        cameraWaiting = true
        lastSpokenCountdown = nil
        audio.cancelSpeech()
        audio.startMusic()
        engine.restart()
        snapshot = engine.snapshot
        tracking.start()
    }

    func togglePause() {
        paused ? resume() : pause()
    }

    func pause() {
        guard !paused else { return }
        paused = true
        clock.pause(at: Self.now)
        audio.pauseMusic()
        audio.cancelSpeech()
        lastSpokenCountdown = nil
    }

    func resume() {
        guard paused, !allSetsDone else { return }
        paused = false
        clock.resume(at: Self.now)
        audio.resumeMusic()
    }

    func foreground(permissions: any PermissionManaging) {
        permissions.refresh()
        guard permissions.status(for: .camera) == .authorized else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        if !allSetsDone {
            tracking.start()
        }
        if permissions.status(for: .microphone) == .authorized,
            permissions.status(for: .speechRecognition) == .authorized
        {
            startVoiceListening()
        }
    }

    func background() {
        paused = true
        clock.pause(at: Self.now)
        cameraWaiting = true
        if !allSetsDone, restRemaining == nil {
            engine.invalidateCalibration()
            snapshot = engine.snapshot
        }
        tracking.stop()
        audio.stop()
        voiceListening = false
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func stop() {
        restTask?.cancel()
        restTask = nil
        clock.pause(at: Self.now)
        tracking.stop()
        audio.stop()
        subscriptions.removeAll()
        UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
        started = false
    }

    private func startVoiceListening() {
        voiceAvailable = audio.capability() != .unsupported
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await audio.startListening()
            guard started else { return }
            voiceListening = result == .started
            if result != .started {
                voiceAvailable = false
            }
        }
    }

    private func handle(_ event: AudioEvent) {
        switch event {
        case .command(.pause):
            pause()
        case .command(.resume):
            resume()
        case .command(.stop):
            requestedExit = true
        case .command(.repeatInstruction):
            if snapshot.phase == .complete {
                restart()
            }
        case .listening(let listening):
            voiceListening = listening
        case .voiceUnavailable:
            voiceAvailable = false
            voiceListening = false
        case .interrupted:
            pause()
        case .completed, .cancelled, .feedbackUnavailable, .command:
            break
        }
    }

    private func updateAudio(from previous: BalanceSnapshot, to current: BalanceSnapshot) {
        if exercise.isSitToStand {
            updateSitToStandAudio(from: previous, to: current)
            return
        }

        if speakCalibrationGuidanceIfNeeded(current) {
            return
        }

        if current.metrics.completedTouches > previous.metrics.completedTouches {
            lastSpokenCountdown = nil
            let key = completionGuidanceKey(for: current)
            audio.play(id: UUID(), cue: .guidance(prefix: .target, key: key))
            return
        }

        if current.activeArm != previous.activeArm
            || (previous.phase == .returning && current.phase == .reaching)
        {
            lastSpokenCountdown = nil
            let key = current.activeArm == .right
                ? exercise.key("voice.rightTarget")
                : exercise.key("voice.leftTarget")
            audio.play(id: UUID(), cue: .guidance(prefix: .target, key: key))
            return
        }

        if previous.phase == .calibrating || previous.phase == .calibratingRange,
            current.phase == .reaching
        {
            let key = current.activeArm == .right
                ? exercise.key("voice.rightTarget")
                : exercise.key("voice.leftTarget")
            audio.play(id: UUID(), cue: .guidance(prefix: .target, key: key))
            return
        }

        if !paused, current.phase == .calibrating || current.phase == .calibratingRange,
            let remaining = current.calibrationCountdown {
            guard remaining != lastSpokenCountdown else { return }
            lastSpokenCountdown = remaining
            audio.play(id: UUID(), cue: .count(remaining))
            return
        }

        // Speak exactly the number drawn in the bubble, for the reach hold and the return hold.
        guard !paused,
            current.phase == .holding || current.phase == .returning,
            let remaining = current.overlay?.holdSecondsRemaining
        else {
            lastSpokenCountdown = nil
            return
        }
        guard remaining != lastSpokenCountdown else { return }
        // While guidance plays, leave it unspoken; the next frame says whatever the bubble shows then.
        guard audio.canSpeakHoldNumber else { return }
        lastSpokenCountdown = remaining
        audio.play(id: UUID(), cue: .holdSecond(remaining))
    }

    /// Reads each new instruction aloud and counts the calibration and countdown seconds, so the
    /// patient can follow without looking at the screen. Repetitions are confirmed with a chime.
    private func updateSitToStandAudio(from previous: BalanceSnapshot, to current: BalanceSnapshot) {
        guard !paused, !cameraWaiting else {
            return
        }

        if current.metrics.completedTouches > previous.metrics.completedTouches {
            lastSpokenCountdown = nil
            let key = completionGuidanceKey(for: current)
            audio.play(id: UUID(), cue: .guidance(prefix: .target, key: key))
            return
        }

        if let remaining = current.calibrationCountdown {
            guard remaining != lastSpokenCountdown else {
                return
            }

            lastSpokenCountdown = remaining
            audio.play(id: UUID(), cue: .count(remaining))
            return
        }

        lastSpokenCountdown = nil

        guard current.phase != .complete,
              current.instructionKey != previous.instructionKey else {
            return
        }

        // Any prefix other than the target chime speaks the line directly.
        audio.play(id: UUID(), cue: .guidance(prefix: .towelGrab, key: current.instructionKey))
    }

    /// Explains the starting pose, then the end pose, aloud as each calibration step begins,
    /// the way the finger exercises narrate their instructions.
    /// - Returns: whether guidance was spoken this frame.
    private func speakCalibrationGuidanceIfNeeded(_ current: BalanceSnapshot) -> Bool {
        guard exercise.isRotation, exercise != .shoulderFlexion else {
            return false
        }

        let key: String

        switch current.phase {
        case .findingBody, .calibrating:
            key = exercise.key("calibration.startHint")
        case .calibratingRange:
            key = exercise.key("calibration.endHint")
        default:
            spokenCalibrationKey = nil
            return false
        }

        guard !paused, !cameraWaiting, key != spokenCalibrationKey else {
            return false
        }

        spokenCalibrationKey = key
        // Any prefix other than the target chime speaks the line directly.
        audio.play(id: UUID(), cue: .guidance(prefix: .towelGrab, key: key))

        return true
    }

    private func completionGuidanceKey(for snapshot: BalanceSnapshot) -> String {
        if snapshot.phase == .complete {
            // Between sets the patient rests; only the last set is announced as complete.
            return setNumber < totalSets ? "session.rest" : exercise.key("voice.complete")
        }
        // Sit to stand has no arms to switch.
        guard !exercise.isSitToStand else {
            return exercise.key("voice.returnSameSide")
        }
        return snapshot.armSelection == .both
            ? exercise.key("voice.returnAndSwitch")
            : exercise.key("voice.returnSameSide")
    }
}
