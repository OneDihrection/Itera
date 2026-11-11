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
    /// The tracked skeleton from the first camera frame, shown until the engine draws its own overlay.
    private(set) var livePose: LivePose.Skeleton?
    @ObservationIgnored private var livePoseTracker = LivePose()
    private(set) var permissionDenied = false
    private(set) var cameraWaiting = true
    private(set) var failure: String?
    private(set) var paused = false
    private(set) var voiceListening = false
    private(set) var voiceAvailable = true
    private(set) var requestedExit = false
    let holdSeconds: Int
    let exercise: BalanceExercise

    private enum OpeningCue: String {
        case intro = "calibration.intro"
        case tryMovement = "calibration.try"
        case complete = "calibration.complete"
        case countdown = "calibration.countdown"
    }

    private var openingCue: OpeningCue? = .intro
    private var calibrationFinished = false
    private(set) var practiceCountdown: Int?
    @ObservationIgnored private var openingSpeechID: UUID?
    @ObservationIgnored private var openingSpeechDeadline: Double?
    @ObservationIgnored private var countdownDeadline: Double?

    var calibrationMessage: String? {
        if let openingCue, openingCue != .countdown {
            return openingCue.rawValue
        }
        return calibrationFinished ? nil : "calibration.try"
    }

    var countdownOverlaySeconds: Int? {
        openingCue == .countdown ? 3 : practiceCountdown
    }

    // MARK: Sets

    /// The set being practiced, from 1.
    private(set) var setNumber = 1
    let totalSets: Int
    let restSeconds: Int
    /// Repetitions of every finished set, in order.
    private(set) var setResults: [Int] = []
    /// Seconds left before the next set while resting between sets, otherwise `nil`.
    private(set) var restRemaining: Int?

    var restBreath: RestBreath? {
        restRemaining.map { RestBreath(elapsed: Double(restSeconds - $0)) }
    }

    /// True once the last set is finished.
    var allSetsDone: Bool {
        setResults.count >= totalSets
    }

    @ObservationIgnored let tracking: BodyTrackingService
    @ObservationIgnored private let audio: SessionAudioService
    @ObservationIgnored private var engine: any BalanceMovementEngine
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var viewport: TherapyViewport?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var wasIdleTimerDisabled = false
    @ObservationIgnored private var lastSpokenCountdown: Int?
    /// The calibration pose already explained aloud, so each is spoken once per calibration.
    @ObservationIgnored private var spokenCalibrationKey: String?
    /// Practice time shown on the pause dialog; explicit pauses do not count.
    @ObservationIgnored private var clock = SessionDurationClock()
    @ObservationIgnored private var restTask: Task<Void, Never>?

    // MARK: History

    /// A summary could not be saved; the completion page offers a retry.
    private(set) var historySaveFailed = false
    @ObservationIgnored private let repository: any SessionRepository
    @ObservationIgnored private let settings: BalancePracticeSettings
    @ObservationIgnored private var log: BalanceSessionLog
    /// Per-repetition metrics and key-repetition skeletons for the current set.
    @ObservationIgnored private var recorder: KeyRepRecorder
    @ObservationIgnored private var pendingSaves: [PendingSave] = []
    @ObservationIgnored private var saving = false
    @ObservationIgnored private var recovered = false

    private enum PendingSave {
        case checkpoint(SessionCheckpoint)
        case finalize(SessionSummary)
        case keyReps(sessionID: UUID, ActivityKeyReps)
    }

    init(
        tracking: BodyTrackingService,
        audio: SessionAudioService,
        repository: any SessionRepository,
        settings: BalancePracticeSettings,
        exercise: BalanceExercise = .crossMidline
    ) {
        let repetitions = settings.repetitions
        let holdSeconds = settings.holdSeconds
        let armSelection = settings.armSelection

        self.tracking = tracking
        self.audio = audio
        self.repository = repository
        self.settings = settings
        let log = Self.makeLog(exercise: exercise, settings: settings)
        self.log = log
        recorder = KeyRepRecorder(activity: log.activity)
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

        tracking.frames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }
                self.livePose = self.livePoseTracker.skeleton(for: frame)

                guard self.advanceOpeningIfReady(at: frame.timestamp) else {
                    if self.paused {
                        self.engine.consume(frame, scoringEnabled: false)
                    } else if !self.cameraWaiting {
                        self.showSkeletonWhileGated(frame)
                    }
                    return
                }
                let previous = self.snapshot
                self.engine.consume(frame, scoringEnabled: !self.paused)
                self.snapshot = self.engine.snapshot
                self.record(frame, previous: previous)
                if self.updateCalibrationTransition(frame) {
                    return
                }
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
                    self.clearLivePose()
                    self.interruptOpening()
                case .discontinuity:
                    self.cameraWaiting = true
                    self.clearLivePose()
                    self.recorder.discardCurrentRep()
                    self.resetOpening()
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
        if !paused, !allSetsDone {
            audio.startMusic()
        }
        let microphone = await permissions.request(.microphone)
        let speech = await permissions.request(.speechRecognition)
        if microphone == .authorized, speech == .authorized {
            startVoiceListening()
        } else {
            voiceAvailable = false
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
        recordSet(outcome: .completed, completedWork: snapshot.metrics.completedTouches)

        guard !allSetsDone else {
            finishLog(stopped: false)
            clock.pause(at: Self.now)
            tracking.stop()
            audio.stopMusic()
            return
        }

        restRemaining = restSeconds
        speakRestBreath()
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

            let previousPhase = restBreath?.phase
            restRemaining = remaining - 1
            if remaining > 1, restBreath?.phase != previousPhase {
                speakRestBreath()
            }
        }

        startNextSet()
    }

    private func speakRestBreath() {
        guard !paused, let phase = restBreath?.phase else {
            return
        }
        audio.cancelSpeech()
        audio.speak(id: UUID(), key: phase.key)
    }

    /// Keeps the calibration: the patient starts the next set from the usual return to start.
    private func startNextSet() {
        guard restRemaining != nil, !allSetsDone else {
            return
        }

        restRemaining = nil
        audio.cancelSpeech()
        setNumber += 1
        lastSpokenCountdown = nil
        engine.nextSet()
        snapshot = engine.snapshot
        openingCue = .countdown
    }

    #if DEBUG
    /// Developer shortcut: records every remaining set as completed at the goal, then ends like the
    /// last set does. The credited work is invented, so this exists only in debug builds.
    func finishExerciseForDebug() {
        guard !allSetsDone else {
            return
        }

        restTask?.cancel()
        restTask = nil
        restRemaining = nil
        paused = false
        audio.cancelSpeech()

        while !allSetsDone {
            setNumber = setResults.count + 1
            setResults.append(settings.repetitions)

            // Invented sets carry no metrics or key-repetition skeletons.
            recorder = KeyRepRecorder(activity: log.activity)
            recordSet(outcome: .completed, completedWork: settings.repetitions)
        }

        finishLog(stopped: false)
        clock.pause(at: Self.now)
        tracking.stop()
        clearLivePose()
        audio.stopMusic()
    }
    #endif

    /// The camera frame in points, so the engine sizes bubbles like the other exercises.
    func viewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        viewport = TherapyViewport(width: size.width, height: size.height)
        engine.viewport = viewport
    }

    func previewReady(_ ready: Bool) {
        if ready { cameraWaiting = false }
    }

    func orientationChanged(right: Bool) {
        tracking.configure(landscapeRight: right)
    }

    func restart() {
        // A repeat is a new session; whatever was practiced before is saved first.
        finishLog(stopped: !allSetsDone)
        log = Self.makeLog(exercise: exercise, settings: settings)
        recorder = KeyRepRecorder(activity: log.activity)
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
        engine.viewport = viewport
        resetOpening()
        snapshot = engine.snapshot
        tracking.start()
    }

    func togglePause() {
        paused ? resume() : pause()
    }

    func pause() {
        guard !paused else { return }
        paused = true
        recorder.discardCurrentRep()
        clock.pause(at: Self.now)
        audio.pauseMusic()
        interruptOpening()
        audio.cancelSpeech()
        lastSpokenCountdown = nil
    }

    func resume() {
        guard paused, !allSetsDone else { return }
        paused = false
        clock.resume(at: Self.now)
        audio.resumeMusic()
        speakRestBreath()
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
        recorder.discardCurrentRep()
        clock.pause(at: Self.now)
        cameraWaiting = true
        if !allSetsDone, restRemaining == nil {
            engine.invalidateCalibration()
            resetOpening()
            snapshot = engine.snapshot
        }
        tracking.stop()
        clearLivePose()
        audio.stop()
        voiceListening = false
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func stop() {
        saveUnfinishedSession()
        restTask?.cancel()
        restTask = nil
        clock.pause(at: Self.now)
        tracking.stop()
        clearLivePose()
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
            if !paused, !allSetsDone {
                audio.startMusic()
            }
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
        case .completed(let id, _):
            if id == openingSpeechID {
                completeOpeningCue()
            }
        case .cancelled, .feedbackUnavailable, .command:
            break
        }
    }

    /// Calibration guidance gates the start of capture, and the countdown gates practice.
    private func advanceOpeningIfReady(at timestamp: Double) -> Bool {
        guard !paused, !cameraWaiting else {
            return paused && openingCue == nil && practiceCountdown == nil
        }

        if let openingCue {
            if let deadline = openingSpeechDeadline, timestamp >= deadline {
                interruptOpening()
                audio.cancelSpeech()
                completeOpeningCue()
            } else if openingSpeechID == nil {
                let id = UUID()
                openingSpeechID = id
                openingSpeechDeadline = timestamp + 8
                audio.speak(id: id, key: openingCue.rawValue)
            }
            return false
        }

        guard !exercise.isSitToStand, practiceCountdown != nil else {
            return true
        }

        let deadline = countdownDeadline ?? timestamp + 3
        countdownDeadline = deadline
        let remaining = Int(ceil(deadline - timestamp))
        guard remaining > 0 else {
            practiceCountdown = nil
            countdownDeadline = nil
            lastSpokenCountdown = nil
            audio.speak(id: UUID(), key: snapshot.instructionKey)
            return true
        }

        practiceCountdown = remaining
        speakCountdown(remaining)
        return false
    }

    private func clearLivePose() {
        livePose = nil
        livePoseTracker.reset()
    }

    /// Shows the live skeleton while spoken guidance or the countdown holds practice back, so the
    /// patient sees tracking at once. Scoring stays off, so calibration and holds do not advance.
    private func showSkeletonWhileGated(_ frame: TrackingObservation) {
        // Sit-to-stand suspends its activity on unscored frames and draws no overlay from them.
        guard !exercise.isSitToStand else {
            return
        }

        engine.consume(frame, scoringEnabled: false)
        snapshot.overlay = engine.snapshot.overlay
    }

    private func updateCalibrationTransition(_ frame: TrackingObservation) -> Bool {
        guard !paused else {
            return true
        }

        let sittingCountdown = exercise.isSitToStand && snapshot.instructionKey == "session.countdown"
        if !calibrationFinished {
            let reachedPracticeStart = exercise.isSitToStand
                ? sittingCountdown
                : snapshot.phase == .reaching || snapshot.phase == .holding || snapshot.phase == .returning
            guard reachedPracticeStart else {
                return false
            }

            calibrationFinished = true
            openingCue = .complete
            audio.cancelSpeech()
            if exercise.isSitToStand {
                // Restart the seated countdown after both announcements finish.
                engine.consume(frame, scoringEnabled: false)
            }
            return true
        }

        if exercise.isSitToStand {
            practiceCountdown = sittingCountdown ? snapshot.calibrationCountdown : nil
        }
        return false
    }

    private func completeOpeningCue() {
        guard !paused, !cameraWaiting else {
            interruptOpening()
            return
        }

        openingSpeechID = nil
        openingSpeechDeadline = nil
        switch openingCue {
        case .intro:
            openingCue = .tryMovement
        case .complete:
            openingCue = .countdown
        case .countdown:
            openingCue = nil
            if !exercise.isSitToStand {
                practiceCountdown = 3
            }
        case .tryMovement, nil:
            openingCue = nil
        }
    }

    private func interruptOpening() {
        openingSpeechID = nil
        openingSpeechDeadline = nil
        countdownDeadline = nil
    }

    private func resetOpening() {
        interruptOpening()
        openingCue = .intro
        calibrationFinished = false
        practiceCountdown = nil
    }

    private func speakCountdown(_ remaining: Int) {
        guard remaining != lastSpokenCountdown else {
            return
        }
        lastSpokenCountdown = remaining
        audio.play(id: UUID(), cue: .countdown(remaining))
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
            audio.speak(id: UUID(), key: key)
            return
        }

        if previous.phase == .calibrating || previous.phase == .calibratingRange,
            current.phase == .reaching
        {
            let key = current.activeArm == .right
                ? exercise.key("voice.rightTarget")
                : exercise.key("voice.leftTarget")
            audio.speak(id: UUID(), key: key)
            return
        }

        // Holds are not counted aloud, during calibration or practice: the bubble and its
        // timer show the seconds, and the voice stays for instructions.
        lastSpokenCountdown = nil
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

        // Only the countdown before practice is counted aloud; the seated hold is shown, not spoken.
        if let remaining = current.calibrationCountdown, current.instructionKey == "session.countdown" {
            speakCountdown(remaining)
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

    // MARK: - Recording and history

    private static func makeLog(exercise: BalanceExercise, settings: BalancePracticeSettings) -> BalanceSessionLog {
        BalanceSessionLog(
            exercise: exercise,
            side: settings.armSelection.initialArm.therapySide,
            alternatesSides: settings.armSelection == .both,
            goal: settings.repetitions,
            sets: settings.sets,
            restSeconds: settings.restSeconds
        )
    }

    /// Feeds the recorder once calibration and the countdown are over. The frame that completes
    /// the set still counts, because it credits the last repetition.
    private func record(_ frame: TrackingObservation, previous: BalanceSnapshot) {
        let practicing: Bool

        switch snapshot.phase {
        case .reaching, .holding:
            practicing = true
        case .returning:
            // Sit-to-stand returns to the seat only before practice.
            practicing = !exercise.isSitToStand
        case .complete:
            practicing = previous.phase != .complete
        case .findingBody, .calibrating, .calibratingRange:
            practicing = false
        }

        let counted = practicing
            && calibrationFinished
            && openingCue == nil
            && practiceCountdown == nil
            && !paused
        let tracked = snapshot.overlay != nil

        recorder.observe(
            frame,
            counted: counted,
            count: snapshot.metrics.completedTouches,
            angle: tracked ? recordedAngle : nil,
            side: exercise.isSitToStand ? nil : snapshot.activeArm.therapySide
        )
    }

    /// The engine's own estimate: forearm rotation or shoulder lift, or knee extension for
    /// sit-to-stand. Cross-midline has no single angle.
    private var recordedAngle: Double? {
        switch exercise {
        case .externalRotation, .internalRotation, .shoulderFlexion:
            return snapshot.rotationDegrees
        case .sitToStand:
            return snapshot.kneeAngle > 0 ? snapshot.kneeAngle : nil
        case .crossMidline:
            return nil
        }
    }

    /// Adds a set to the session history with its metrics and replays, then starts a fresh recorder.
    private func recordSet(outcome: ActivityOutcome, completedWork: Int) {
        let metrics = recorder.metrics
        let executionID = log.recordSet(
            number: setNumber,
            completedWork: completedWork,
            outcome: outcome,
            repMetrics: metrics.isEmpty ? nil : metrics
        )

        if let keyReps = recorder.keyReps(executionID: executionID, setNumber: setNumber) {
            queue(.keyReps(sessionID: log.id, keyReps))
        }

        queue(.checkpoint(log.checkpoint))
        recorder = KeyRepRecorder(activity: log.activity)
    }

    private func finishLog(stopped: Bool) {
        guard let summary = log.finalize(stopped: stopped) else {
            return
        }

        queue(.finalize(summary))
    }

    /// Leaving early keeps the credited repetitions of the set in progress, labeled interrupted.
    private func saveUnfinishedSession() {
        guard !log.finalized else {
            return
        }

        let inProgress = restRemaining == nil && !allSetsDone
        let work = snapshot.metrics.completedTouches

        if inProgress, work > 0 {
            recordSet(outcome: .interrupted, completedWork: work)
        }

        finishLog(stopped: true)
    }

    func retryHistorySave() {
        historySaveFailed = false
        drainSaves()
    }

    private func queue(_ save: PendingSave) {
        pendingSaves.append(save)
        drainSaves()
    }

    /// Saves run one at a time, in order. A failed summary save stops the queue so a retry can
    /// resume it; a failed replay save is logged and skipped, since replays are not history.
    private func drainSaves() {
        guard !saving, !historySaveFailed, !pendingSaves.isEmpty else {
            return
        }

        saving = true

        Task {
            defer { saving = false }

            do {
                if !recovered {
                    try await repository.recoverInterrupted()
                    recovered = true
                }
            } catch {
                historySaveFailed = true
                return
            }

            while let save = pendingSaves.first {
                do {
                    try await perform(save)
                } catch {
                    if case .keyReps = save {
                        NSLog("Key repetition save failed: %@", error.localizedDescription)
                    } else {
                        historySaveFailed = true
                        return
                    }
                }

                pendingSaves.removeFirst()
            }
        }
    }

    private func perform(_ save: PendingSave) async throws {
        switch save {
        case .checkpoint(let checkpoint):
            try await repository.checkpoint(checkpoint)
        case .finalize(let summary):
            try await repository.finalize(summary)
        case .keyReps(let sessionID, let keyReps):
            try await repository.saveKeyReps(keyReps, sessionID: sessionID)
        }
    }
}
