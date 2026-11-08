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

    init(
        tracking: BodyTrackingService,
        audio: SessionAudioService,
        repetitions: Int,
        holdSeconds: Int,
        armSelection: BalanceArmSelection,
        exercise: BalanceExercise = .crossMidline
    ) {
        self.tracking = tracking
        self.audio = audio
        self.holdSeconds = min(20, max(3, holdSeconds))
        self.exercise = exercise
        switch exercise {
        case .crossMidline:
            engine = CrossMidlineBalanceEngine(
                goal: repetitions,
                holdDuration: Double(holdSeconds),
                armSelection: armSelection
            )
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
                    self.tracking.stop()
                    self.audio.stopMusic()
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
        audio.prepare()
        let microphone = await permissions.request(.microphone)
        let speech = await permissions.request(.speechRecognition)
        if microphone == .authorized, speech == .authorized {
            startVoiceListening()
        } else {
            voiceAvailable = false
        }
        if !paused, snapshot.phase != .complete {
            audio.startMusic()
        }
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
        audio.pauseMusic()
        audio.cancelSpeech()
        lastSpokenCountdown = nil
    }

    func resume() {
        guard paused, snapshot.phase != .complete else { return }
        paused = false
        audio.resumeMusic()
    }

    func foreground(permissions: any PermissionManaging) {
        permissions.refresh()
        guard permissions.status(for: .camera) == .authorized else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        if snapshot.phase != .complete {
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
        cameraWaiting = true
        if snapshot.phase != .complete {
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

        guard !paused,
            current.phase == .holding,
            let remaining = current.overlay?.holdSecondsRemaining
        else {
            lastSpokenCountdown = nil
            return
        }
        guard remaining != lastSpokenCountdown else { return }
        lastSpokenCountdown = remaining
        audio.play(id: UUID(), cue: .count(remaining))
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
            return exercise.key("voice.complete")
        }
        return snapshot.armSelection == .both
            ? exercise.key("voice.returnAndSwitch")
            : exercise.key("voice.returnSameSide")
    }
}
