//
//  BalanceSessionViewModel.swift
//  Tuntun
//
//  Created by Gracia A on 02/11/2026.
//

import Combine
import Observation
import UIKit

@MainActor
protocol BalanceSessionViewModelProtocol: AnyObject, Observable {
    var exercise: BalanceExercise { get }
    var snapshot: BalanceSnapshot { get }
    var permissionDenied: Bool { get }
    /// Names every missing permission together while `permissionDenied`.
    var permissionMessageKey: String { get }
    /// False when Settings cannot fix it (restricted access).
    var permissionOffersSettings: Bool { get }
    var cameraWaiting: Bool { get }
    var failure: String? { get }
    var paused: Bool { get }
    var demoRevision: Int { get }
    var calibrationMessage: String? { get }
    /// True once calibration finishes: practice shows the demonstration's target pose still.
    var demoHoldsPeak: Bool { get }
    var countdownOverlaySeconds: Int? { get }
    /// Whether the patient is in position, for the camera's tracking-status chip; nil hides it.
    var trackingPositioned: Bool? { get }
    /// Whether the chip is muted because a cue or the countdown holds movement back.
    var trackingMuted: Bool { get }
    var setNumber: Int { get }
    var totalSets: Int { get }
    var setResults: [Int] { get }
    var restRemaining: Int? { get }
    var restBreath: RestBreath? { get }
    /// The rest page's cue and breathing intensity: the scripted rest's line, or the timed rhythm.
    var restCueKey: String? { get }
    var restIntensity: Double { get }
    /// Whether an Indonesian 2026-11-23 script narrates this session.
    var usesScript: Bool { get }
    var allSetsDone: Bool { get }
    var historySaveFailed: Bool { get }
    var elapsedSeconds: Int { get }
    /// True until `start()` has prepared audio and started capture.
    var isPreparing: Bool { get }
    /// True from End until the page is replaced.
    var isFinishing: Bool { get }
    /// The capture owner the camera preview attaches to.
    var trackingService: BodyTrackingService { get }

    func start(permissionService: any PermissionServiceProtocol) async
    func foreground(permissionService: any PermissionServiceProtocol)
    /// Rechecks permissions from the permission panel and continues or starts when all are granted.
    func retryPermissions(permissionService: any PermissionServiceProtocol)
    func background()
    func viewport(_ size: CGSize)
    func previewReady(_ ready: Bool)
    func orientationChanged(right: Bool)
    func retryCamera()
    func restart()
    func pause()
    func resume()
    func stop()
    func end() async
    func openSettings()
    func retryHistorySave()
    /// Skip on the rest page: ends the rest between sets and starts the next set.
    func skipRest()
    #if DEBUG
    func finishExerciseForDebug()
    #endif
}

@MainActor
@Observable
final class BalanceSessionViewModel: BalanceSessionViewModelProtocol {
    private(set) var snapshot = BalanceSnapshot()
    /// Camera, microphone and speech recognition are all required: there is no session without
    /// voice commands (ADR-005), so a missing one blocks like the camera instead of going silent.
    private var permissionRequirement = PermissionRequirement.granted
    private(set) var isPreparing = true
    private(set) var isFinishing = false
    private(set) var cameraWaiting = true
    private(set) var failure: String?
    private(set) var paused = false
    private(set) var voiceListening = false
    private(set) var voiceAvailable = true
    /// Increases when the demonstration switches to the other arm, so the screen can highlight it.
    private(set) var demoRevision = 0
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
    /// The opening cue being spoken; practice waits for it or its 8 s watchdog.
    @ObservationIgnored private var openingGate: GuidanceGate?
    @ObservationIgnored private var countdownDeadline: Double?

    var demoHoldsPeak: Bool {
        calibrationFinished
    }

    var calibrationMessage: String? {
        if let openingCue, openingCue != .countdown {
            return openingCue.rawValue
        }
        return calibrationFinished ? nil : "calibration.try"
    }

    var countdownOverlaySeconds: Int? {
        openingCue == .countdown ? practiceCountdownLength : practiceCountdown
    }

    // MARK: Tracking status

    /// Losing the body shows after 1 s and finding it again after 0.5 s, as in the guided
    /// movement exercises, so a dropped frame does not flicker the chip.
    private static let trackingLostDelay = 1.0
    private static let trackingFoundDelay = 0.5

    /// The debounced in-position state; written only when it changes.
    private(set) var trackingSettled = false
    /// True while spoken guidance or the countdown holds practice back; written only when it changes.
    private(set) var trackingMuted = false
    /// When the engine's state began to differ from `trackingSettled`.
    @ObservationIgnored private var trackingChangeSince: Double?

    var trackingPositioned: Bool? {
        guard !isPreparing,
              !isFinishing,
              !permissionDenied,
              failure == nil,
              !cameraWaiting,
              !paused,
              restRemaining == nil,
              !allSetsDone,
              countdownOverlaySeconds == nil else {
            return nil
        }

        return trackingSettled
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

    @ObservationIgnored let trackingService: BodyTrackingService
    @ObservationIgnored private let audioService: SessionAudioService
    @ObservationIgnored private var engine: any BalanceMovementEngine
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var viewport: TherapyViewport?
    @ObservationIgnored private var started = false
    /// Guards `start` while it awaits prompts: those turn the scene inactive and active again,
    /// and that foreground must neither start a second session nor show the panel under a prompt.
    @ObservationIgnored private var startingSession = false
    @ObservationIgnored private var wasIdleTimerDisabled = false
    @ObservationIgnored private var lastSpokenCountdown: Int?
    /// The calibration pose already explained aloud, so each is spoken once per calibration.
    @ObservationIgnored private var spokenCalibrationKey: String?
    /// Practice time shown on the pause dialog; explicit pauses do not count.
    @ObservationIgnored private var clock = SessionDurationClock()
    @ObservationIgnored private var restTask: Task<Void, Never>?

    // MARK: Script

    /// The exercise's 2026-11-23 script in an Indonesian session, or nil.
    @ObservationIgnored private let script: BalanceScript?
    /// Lines still to follow the one being spoken, and what runs after the last.
    @ObservationIgnored private var scriptQueue: [NarrationLine] = []
    @ObservationIgnored private var scriptLineID: UUID?
    @ObservationIgnored private var scriptCompletion: (() -> Void)?
    /// The script cue already spoken, so each is said once.
    @ObservationIgnored private var spokenScriptCue: String?
    @ObservationIgnored private var spokenHoldSecond: String?
    /// The latest frame shows the joints the script asks the camera to see.
    @ObservationIgnored private var bodyInView = false
    @ObservationIgnored private var bodyReminderAt: Double?
    /// The scripted short rest between sets: opening, three breaths and closing.
    private(set) var scriptedRest: BreathingRest?
    /// Seconds between the "Pastikan … terlihat di kamera" reminders while the body is not in view.
    private static let bodyReminderSeconds = 8.0

    var usesScript: Bool {
        script != nil
    }

    var restCueKey: String? {
        guard restRemaining != nil else {
            return nil
        }

        guard script != nil else {
            return restBreath?.phase.key
        }

        // While the summary is spoken the page already shows the rest's opening line.
        return scriptedRest?.cueKey(prefix: "scripted.") ?? "scripted.rest.opening.1"
    }

    var restIntensity: Double {
        guard script != nil else {
            return restBreath?.intensity ?? 0
        }

        return scriptedRest?.intensity ?? 0
    }

    /// The scripts count three seconds before later sets as "Set selanjutnya … 5, 4, 3, 2, 1".
    private var practiceCountdownLength: Int {
        script != nil && setNumber > 1 ? 5 : 3
    }

    // MARK: History

    /// A summary could not be saved; the completion page offers a retry.
    private(set) var historySaveFailed = false
    @ObservationIgnored private let repository: any SessionRepository
    @ObservationIgnored private let settings: BalancePracticeSettings
    @ObservationIgnored private var log: BalanceSessionLog
    /// Per-repetition metrics and key-repetition skeletons for the current set.
    @ObservationIgnored private var recorder: KeyRepRecorder
    /// Seconds of the current set credited from counted, tracked frames; saved with the set.
    @ObservationIgnored private var practiceSeconds = 0.0
    @ObservationIgnored private var lastRecordedFrame: Double?
    @ObservationIgnored private var pendingSaves: [PendingSave] = []
    @ObservationIgnored private var saving = false
    @ObservationIgnored private var recovered = false

    /// Read once at session start, so a settings change never affects a running session.
    @ObservationIgnored private var replayRecording = ReplayRecording.off

    private enum PendingSave {
        case checkpoint(SessionCheckpoint)
        case finalize(SessionSummary)
    }

    init(
        trackingService: BodyTrackingService,
        audioService: SessionAudioService,
        repository: any SessionRepository,
        settings: BalancePracticeSettings,
        exercise: BalanceExercise = .crossMidline
    ) {
        let repetitions = settings.repetitions
        let holdSeconds = settings.holdSeconds
        let armSelection = settings.armSelection

        self.trackingService = trackingService
        self.audioService = audioService
        self.repository = repository
        self.settings = settings
        let log = Self.makeLog(exercise: exercise, settings: settings)
        self.log = log
        recorder = KeyRepRecorder(activity: log.activity)
        self.holdSeconds = min(20, max(3, holdSeconds))
        self.exercise = exercise
        totalSets = settings.sets
        restSeconds = settings.restSeconds
        script = AppLanguage.selected == .indonesian
            ? BalanceScriptGuidance.script(for: exercise, arms: armSelection)
            : nil
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

    func start(permissionService: any PermissionServiceProtocol) async {
        guard !started, !startingSession else { return }
        startingSession = true
        // A retry after the permission panel shows the loading overlay again.
        isPreparing = true
        defer {
            startingSession = false
            isPreparing = false
        }

        // Preparing audio blocks the main actor, so the loading overlay is drawn first.
        try? await Task.sleep(for: TMLoadingOverlay.presentationDelay)

        // Readiness has usually asked already; each request prompts only while still unasked.
        for permission in AppPermission.allCases {
            _ = await permissionService.request(permission)
        }
        guard updatePermissions(permissionService) else {
            return
        }

        started = true
        wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        replayRecording = PracticePreferences.replayRecordingLevel
        trackingService.clips.reset()
        trackingService.clips.configure(privacy: PracticePreferences.repClipPrivacy)

        trackingService.frames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }

                if let script = self.script {
                    self.bodyInView = BalanceScriptGuidance.bodyVisible(frame, script: script)
                }
                guard self.advanceOpeningIfReady(at: frame.timestamp) else {
                    self.setTrackingMuted(true)
                    if self.paused {
                        self.engine.consume(frame, scoringEnabled: false)
                    } else if !self.cameraWaiting {
                        self.showSkeletonWhileGated(frame)
                    }
                    self.updateTrackingStatus(at: frame.timestamp)
                    return
                }
                self.setTrackingMuted(false)
                let previous = self.snapshot
                self.engine.consume(frame, scoringEnabled: !self.paused)
                self.snapshot = self.engine.snapshot
                self.updateTrackingStatus(at: frame.timestamp)
                self.record(frame, previous: previous)
                if self.updateCalibrationTransition(frame) {
                    return
                }
                self.updateAudio(from: previous, to: self.snapshot)
                self.updateDemoArm(from: previous)
                if previous.phase != .complete, self.snapshot.phase == .complete {
                    self.finishSet()
                }
            }
            .store(in: &subscriptions)

        trackingService.availability
            .receive(on: DispatchQueue.main)
            .sink { [weak self] availability in
                guard let self else { return }
                switch availability {
                case .ready:
                    self.cameraWaiting = false
                    self.failure = nil
                case .waiting:
                    self.cameraWaiting = true
                    self.interruptOpening()
                case .discontinuity:
                    self.cameraWaiting = true
                    self.recorder.discardCurrentRep()
                    self.resetOpening()
                    self.engine.invalidateCalibration()
                    self.snapshot = self.engine.snapshot
                }
            }
            .store(in: &subscriptions)

        trackingService.failures
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.failure = error
                self?.cameraWaiting = true
            }
            .store(in: &subscriptions)

        audioService.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &subscriptions)

        trackingService.start()
        clock.resume(at: Self.now)
        audioService.prepare()
        if !paused, !allSetsDone {
            audioService.startMusic()
        }
        isPreparing = false
        startVoiceListening()
    }

    // MARK: - Permissions

    var permissionDenied: Bool {
        permissionRequirement != .granted
    }

    var permissionMessageKey: String {
        permissionRequirement.messageKey ?? "home.permissionUnavailable"
    }

    var permissionOffersSettings: Bool {
        guard case .denied = permissionRequirement else {
            return false
        }

        return true
    }

    /// Evaluates all three permissions and returns whether the session may run.
    private func updatePermissions(_ permissionService: any PermissionServiceProtocol) -> Bool {
        permissionRequirement = PermissionRequirement.evaluate(
            AppPermission.allCases,
            in: permissionService
        )

        return permissionRequirement == .granted
    }

    func retryPermissions(permissionService: any PermissionServiceProtocol) {
        foreground(permissionService: permissionService)
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
        let summary = ScriptedSummary.lines(
            completedSets: setResults.count,
            sets: totalSets,
            goal: settings.repetitions
        )

        guard !allSetsDone else {
            finishLog(stopped: false)
            clock.pause(at: Self.now)
            trackingService.stop()
            audioService.stopMusic()
            if script != nil {
                speakScript(summary, chime: true)
            }
            return
        }

        restRemaining = restSeconds
        if script != nil {
            // The summary first, then the scripted rest; the page shows the rest meanwhile.
            restTask?.cancel()
            speakScript(summary, chime: true) { [weak self] in
                self?.beginScriptedRest()
            }
            return
        }
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
        guard script == nil else {
            speakScriptedRestStep()
            return
        }
        guard !paused, let phase = restBreath?.phase else {
            return
        }
        audioService.handOffSpeech()
        audioService.speak(id: UUID(), key: phase.key)
    }

    // MARK: - Scripted rest

    private func beginScriptedRest() {
        guard restRemaining != nil, !allSetsDone else {
            return
        }

        scriptedRest = BreathingRest(openingAfterSet: setResults.count, minimumSeconds: Double(restSeconds))
        speakScriptedRestStep()
        restTask?.cancel()
        restTask = Task { [weak self] in
            await self?.runScriptedRest()
        }
    }

    /// Each step waits for its line and its minimum time; a pause earns no time.
    private func runScriptedRest() async {
        while let rest = scriptedRest, !rest.finished {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard var current = scriptedRest else {
                return
            }
            let step = current.step
            current.tick(Self.now, ready: !paused)
            scriptedRest = current
            if current.step != step, !current.finished {
                speakScriptedRestStep()
            }
        }

        scriptedRest = nil
        startNextSet()
    }

    /// Speaks the scripted rest's current line; the quiet step speaks nothing.
    private func speakScriptedRestStep() {
        guard !paused, let key = scriptedRest?.key else {
            return
        }

        speakScript([NarrationLine(key: "scripted." + key)]) { [weak self] in
            self?.scriptedRest?.guidanceCompleted()
        }
    }

    // MARK: - Script lines

    /// Speaks `lines` one after another, replacing any script lines still queued, then runs
    /// `completion`. `chime` leads the first line with the repetition sound.
    private func speakScript(_ lines: [NarrationLine], chime: Bool = false, completion: (() -> Void)? = nil) {
        scriptQueue = lines
        scriptCompletion = completion
        audioService.handOffSpeech()
        if chime {
            audioService.play(id: UUID(), cue: .target)
        }
        speakNextScriptLine()
    }

    private func speakNextScriptLine() {
        guard !scriptQueue.isEmpty else {
            scriptLineID = nil
            let completion = scriptCompletion
            scriptCompletion = nil
            completion?()
            return
        }

        let line = scriptQueue.removeFirst()
        let id = UUID()
        scriptLineID = id
        if line.isNumber, let number = line.argument {
            audioService.play(id: id, cue: .count(number))
        } else {
            audioService.speak(id: id, key: line.key, argument: line.argument)
        }
    }

    private func clearScriptLines() {
        scriptQueue = []
        scriptLineID = nil
        scriptCompletion = nil
    }

    /// Keeps the calibration: the patient starts the next set from the usual return to start.
    private func startNextSet() {
        guard restRemaining != nil, !allSetsDone else {
            return
        }

        restRemaining = nil
        scriptedRest = nil
        spokenScriptCue = nil
        audioService.handOffSpeech()
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
        audioService.cancelSpeech()

        while !allSetsDone {
            setNumber = setResults.count + 1
            setResults.append(settings.repetitions)

            // Invented sets carry no metrics or key-repetition skeletons.
            recorder = KeyRepRecorder(activity: log.activity)
            recordSet(outcome: .completed, completedWork: settings.repetitions)
        }

        finishLog(stopped: false)
        clock.pause(at: Self.now)
        trackingService.stop()
        audioService.stopMusic()
    }
    #endif

    /// Skip on the rest page: ends the rest between sets now and starts the next set the way an
    /// elapsed rest does. Cancelling the countdown task first makes its sleep throw, so it returns
    /// without calling `startNextSet()` a second time. Ignored while paused, like the rest itself.
    func skipRest() {
        guard restRemaining != nil, !paused, !allSetsDone else {
            return
        }

        restTask?.cancel()
        restTask = nil
        clearScriptLines()
        scriptedRest = nil
        audioService.cancelSpeech()
        startNextSet()
    }

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
        trackingService.configure(landscapeRight: right)
    }

    /// Restarts capture after a camera failure; the next first frame clears the failure.
    func retryCamera() {
        guard !allSetsDone else {
            return
        }

        failure = nil
        trackingService.start()
    }

    func restart() {
        // A repeat is a new session; whatever was practiced before is saved first.
        finishLog(stopped: !allSetsDone)
        log = Self.makeLog(exercise: exercise, settings: settings)
        recorder = KeyRepRecorder(activity: log.activity)
        restTask?.cancel()
        restTask = nil
        restRemaining = nil
        scriptedRest = nil
        clearScriptLines()
        spokenScriptCue = nil
        setNumber = 1
        setResults = []
        clock = SessionDurationClock()
        clock.resume(at: Self.now)
        paused = false
        cameraWaiting = true
        lastSpokenCountdown = nil
        audioService.cancelSpeech()
        audioService.startMusic()
        engine.restart()
        engine.viewport = viewport
        resetOpening()
        snapshot = engine.snapshot
        trackingService.start()
    }

    func togglePause() {
        paused ? resume() : pause()
    }

    func pause() {
        guard !paused else { return }
        paused = true
        recorder.discardCurrentRep()
        clock.pause(at: Self.now)
        audioService.pauseMusic()
        interruptOpening()
        clearScriptLines()
        audioService.cancelSpeech()
        lastSpokenCountdown = nil
        // The interrupted cue is spoken again on resume.
        spokenScriptCue = nil
    }

    func resume() {
        guard paused, !allSetsDone else { return }
        paused = false
        clock.resume(at: Self.now)
        audioService.resumeMusic()
        if script != nil, restRemaining != nil, scriptedRest == nil {
            // A pause cut the summary before its rest began.
            beginScriptedRest()
            return
        }
        speakRestBreath()
    }

    func foreground(permissionService: any PermissionServiceProtocol) {
        guard !startingSession else {
            return
        }

        permissionService.refresh()
        guard updatePermissions(permissionService) else {
            return
        }

        // A start blocked by permissions never ran; granting them in Settings starts it now.
        guard started else {
            Task {
                await start(permissionService: permissionService)
            }
            return
        }

        if !allSetsDone {
            trackingService.start()
        }
        startVoiceListening()
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
        trackingService.stop()
        audioService.stop()
        voiceListening = false
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Runs once: `end()` stops before leaving and the page's disappearance calls it again.
    func stop() {
        guard started else {
            return
        }

        saveUnfinishedSession()
        restTask?.cancel()
        restTask = nil
        clock.pause(at: Self.now)
        trackingService.clips.setEnabled(false)
        trackingService.clips.releaseFrames()
        trackingService.stop()
        audioService.stop()
        subscriptions.removeAll()
        UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
        started = false
    }

    /// Stops the session behind the loading overlay; stopping tears down capture and audio on
    /// the main actor.
    func end() async {
        guard !isFinishing else {
            return
        }

        isFinishing = true
        try? await Task.sleep(for: TMLoadingOverlay.presentationDelay)
        stop()
    }

    private func startVoiceListening() {
        voiceAvailable = audioService.capability() != .unsupported
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await audioService.startListening()
            guard started else { return }
            voiceListening = result == .started
            if !paused, !allSetsDone {
                audioService.startMusic()
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
        case .listening(let listening):
            voiceListening = listening
        case .voiceUnavailable:
            voiceAvailable = false
            voiceListening = false
        case .interrupted:
            pause()
        case .completed(let id, _):
            if openingGate?.id == id {
                completeOpeningCue()
            } else if scriptLineID == id {
                speakNextScriptLine()
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
            if let openingGate, openingGate.expired(at: timestamp) {
                interruptOpening()
                audioService.cancelSpeech()
                completeOpeningCue()
            } else if openingGate == nil {
                if let script {
                    speakScriptOpening(openingCue, script: script, at: timestamp)
                } else {
                    let gate = GuidanceGate(startedAt: timestamp, watchdog: 8)
                    openingGate = gate
                    audioService.speak(id: gate.id, key: openingCue.rawValue)
                }
            }
            return false
        }

        guard !exercise.isSitToStand, practiceCountdown != nil else {
            return true
        }

        let deadline = countdownDeadline ?? timestamp + Double(practiceCountdownLength)
        countdownDeadline = deadline
        let remaining = Int(ceil(deadline - timestamp))
        guard remaining > 0 else {
            practiceCountdown = nil
            countdownDeadline = nil
            lastSpokenCountdown = nil
            // A script speaks the first repetition from the next frame's phase instead.
            if script == nil {
                audioService.speak(id: UUID(), key: snapshot.instructionKey)
            }
            return true
        }

        practiceCountdown = remaining
        speakCountdown(remaining)
        return false
    }

    /// The scripted opening cues: setup, the body check and phase 2's opening, the calibration
    /// ending and the countdown title. Waiting for the body speaks a reminder every 8 s.
    private func speakScriptOpening(_ cue: OpeningCue, script: BalanceScript, at timestamp: Double) {
        let lines: [String]
        switch cue {
        case .intro:
            lines = script.setup
        case .tryMovement:
            guard bodyInView else {
                remindBodyNotVisible(script: script, at: timestamp)
                return
            }
            bodyReminderAt = nil
            lines = script.detected
        case .complete:
            lines = script.calibrationEnding
        case .countdown:
            lines = [setNumber == 1 ? "calibration.countdown" : "scripted.countdown.next"]
        }

        let gate = GuidanceGate(startedAt: timestamp, watchdog: 8 * Double(max(1, lines.count)) + 4)
        openingGate = gate
        speakScript(lines.map { NarrationLine(key: $0) }) { [weak self] in
            self?.completeOpeningCue()
        }
    }

    private func remindBodyNotVisible(script: BalanceScript, at timestamp: Double) {
        guard let since = bodyReminderAt else {
            bodyReminderAt = timestamp
            return
        }

        guard timestamp - since >= Self.bodyReminderSeconds, scriptLineID == nil else {
            return
        }

        bodyReminderAt = timestamp
        speakScript([NarrationLine(key: script.notVisible)])
    }

    /// Follows the engine's tracking state into `trackingSettled` once it has held for its delay.
    private func updateTrackingStatus(at time: Double) {
        let positioned = !engine.snapshot.trackingLost

        guard positioned != trackingSettled else {
            trackingChangeSince = nil
            return
        }

        let since = trackingChangeSince ?? time
        trackingChangeSince = since

        let delay = positioned ? Self.trackingFoundDelay : Self.trackingLostDelay
        guard time - since >= delay else {
            return
        }

        trackingSettled = positioned
        trackingChangeSince = nil
    }

    private func setTrackingMuted(_ muted: Bool) {
        guard trackingMuted != muted else {
            return
        }

        trackingMuted = muted
    }

    /// Shows the live skeleton while spoken guidance or the countdown holds practice back, so the
    /// patient sees tracking at once. Scoring stays off, so calibration and holds do not advance.
    private func showSkeletonWhileGated(_ frame: TrackingObservation) {
        engine.preview(frame)

        // Sit-to-stand draws no overlay from previews; only its tracking state follows them.
        guard !exercise.isSitToStand else {
            return
        }

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
            audioService.handOffSpeech()
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

        openingGate = nil
        switch openingCue {
        case .intro:
            openingCue = .tryMovement
        case .complete:
            openingCue = .countdown
        case .countdown:
            openingCue = nil
            if !exercise.isSitToStand {
                practiceCountdown = practiceCountdownLength
            }
        case .tryMovement, nil:
            openingCue = nil
        }
    }

    private func interruptOpening() {
        // Only an opening cue's own lines stop here; the summary and rest keep their place.
        if script != nil, openingGate != nil {
            clearScriptLines()
        }
        openingGate = nil
        countdownDeadline = nil
    }

    private func resetOpening() {
        interruptOpening()
        spokenScriptCue = nil
        bodyReminderAt = nil
        openingCue = .intro
        calibrationFinished = false
        practiceCountdown = nil
    }

    private func speakCountdown(_ remaining: Int) {
        guard remaining != lastSpokenCountdown else {
            return
        }
        lastSpokenCountdown = remaining
        audioService.play(id: UUID(), cue: .countdown(remaining))
    }

    private func updateAudio(from previous: BalanceSnapshot, to current: BalanceSnapshot) {
        if let script {
            updateScriptAudio(from: previous, to: current, script: script)
            return
        }

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
            audioService.play(id: UUID(), cue: .guidance(prefix: .target, key: key))
            return
        }

        if current.activeArm != previous.activeArm
            || (previous.phase == .returning && current.phase == .reaching)
        {
            lastSpokenCountdown = nil
            let key = current.activeArm == .right
                ? exercise.key("voice.rightTarget")
                : exercise.key("voice.leftTarget")
            audioService.speak(id: UUID(), key: key)
            return
        }

        if previous.phase == .calibrating || previous.phase == .calibratingRange,
            current.phase == .reaching
        {
            let key = current.activeArm == .right
                ? exercise.key("voice.rightTarget")
                : exercise.key("voice.leftTarget")
            audioService.speak(id: UUID(), key: key)
            return
        }

        // Holds are not counted aloud, during calibration or practice: the bubble and its
        // timer show the seconds, and the voice stays for instructions.
        lastSpokenCountdown = nil
    }

    /// The script's line for the current moment: calibration poses, then each repetition's way
    /// back and target with the previous repetition's praise. Hold seconds are Marizka numbers,
    /// as the scripts' "Tahan 3.. 2.. 1.." say.
    private func updateScriptAudio(from previous: BalanceSnapshot, to current: BalanceSnapshot, script: BalanceScript) {
        guard !paused, !cameraWaiting else {
            return
        }

        if exercise.isSitToStand,
           let completions = current.overlay?.completions,
           completions > previous.overlay?.completions ?? completions {
            audioService.play(id: UUID(), cue: .holdPopped)
        }

        // Sit to stand's own countdown before practice is counted aloud.
        if exercise.isSitToStand, let remaining = current.calibrationCountdown, current.instructionKey == "session.countdown" {
            speakCountdown(remaining)
            return
        }

        if let cue = scriptCue(for: current, script: script), cue.identity != spokenScriptCue {
            spokenScriptCue = cue.identity
            spokenHoldSecond = nil
            speakScript(cue.lines, chime: cue.chime)
            return
        }

        speakHoldSecondIfNeeded(current)
    }

    private func scriptCue(for current: BalanceSnapshot, script: BalanceScript) -> BalanceScriptCue? {
        guard calibrationFinished else {
            return BalanceScriptGuidance.calibrationCue(for: current.phase, script: script)
        }

        guard current.phase != .complete else {
            return nil
        }

        let count = current.metrics.completedTouches
        if exercise.isSitToStand {
            return BalanceScriptGuidance.sitToStandCue(
                phase: current.phase,
                instruction: current.instructionKey,
                count: count,
                set: setNumber,
                goal: settings.repetitions,
                script: script
            )
        }

        return BalanceScriptGuidance.armCue(
            phase: current.phase,
            count: count,
            set: setNumber,
            goal: settings.repetitions,
            script: script
        )
    }

    /// The last three seconds of a hold, as Marizka numbers, while no line is speaking.
    private func speakHoldSecondIfNeeded(_ current: BalanceSnapshot) {
        let remaining = current.calibrationCountdown ?? current.overlay?.holdSecondsRemaining
        guard scriptLineID == nil, let remaining, (1...3).contains(remaining) else {
            return
        }

        let identity = "\(current.phase)-\(current.metrics.completedTouches)-\(setNumber)-\(remaining)"
        guard identity != spokenHoldSecond else {
            return
        }

        spokenHoldSecond = identity
        audioService.play(id: UUID(), cue: .holdSecond(remaining))
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
            audioService.play(id: UUID(), cue: .guidance(prefix: .target, key: key))
            return
        }

        // A held seat, a held stand or a stand in practice popped the hip circle: the pop sound
        // leads into the instruction that changed with it.
        if let completions = current.overlay?.completions,
           completions > previous.overlay?.completions ?? completions {
            lastSpokenCountdown = nil
            audioService.play(
                id: UUID(),
                cue: .guidance(prefix: .holdPopped, key: current.instructionKey)
            )
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
        audioService.play(id: UUID(), cue: .guidance(prefix: .towelGrab, key: current.instructionKey))
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
        audioService.play(id: UUID(), cue: .guidance(prefix: .towelGrab, key: key))

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

        // Practice time follows the guided rule: each counted, tracked frame credits at most
        // 0.2 s, and a gap over 0.3 s credits nothing.
        let gap = lastRecordedFrame.map { frame.timestamp - $0 } ?? 0
        lastRecordedFrame = frame.timestamp

        if counted, tracked, gap > 0, gap <= 0.3 {
            practiceSeconds += min(0.2, gap)
        }

        let clip = recorder.observe(
            frame,
            counted: counted,
            count: snapshot.metrics.completedTouches,
            angle: tracked ? recordedAngle : nil,
            side: exercise.isSitToStand ? nil : snapshot.activeArm.therapySide
        )

        // Kept before recording stops, so the set's last repetition still finds its frames.
        if let clip {
            trackingService.clips.keep(
                group: clip.group,
                repNumber: clip.repNumber,
                from: clip.start,
                to: clip.end,
                retaining: clip.retaining
            )
        }

        trackingService.clips.setEnabled(replayRecording.savesClips && counted)
    }

    /// The engine's own estimate: forearm rotation or shoulder lift, or hip extension for
    /// sit-to-stand. Cross-midline has no single angle.
    private var recordedAngle: Double? {
        switch exercise {
        case .externalRotation, .internalRotation, .shoulderFlexion:
            return snapshot.rotationDegrees
        case .sitToStand:
            return snapshot.hipAngle > 0 ? snapshot.hipAngle : nil
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
            practiceSeconds: practiceSeconds,
            repMetrics: metrics.isEmpty ? nil : metrics
        )
        practiceSeconds = 0

        // The numbers above are kept at every privacy level; the replay only when allowed.
        if replayRecording.savesSkeletons,
           let keyReps = recorder.keyReps(executionID: executionID, setNumber: setNumber)
        {
            saveReplayInBackground(for: keyReps, sessionID: log.id)
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
                    historySaveFailed = true
                    return
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
        }
    }

    /// Replays help review but are not history: a failed save is only logged.
    ///
    /// Rewriting the skeleton file and encoding a long set's clips take time, so both run beside
    /// the save queue instead of in it: the summary is finalized without waiting for them. Each
    /// `saveKeyReps` is one actor call, so sets saved together never interleave.
    private func saveReplayInBackground(for keyReps: ActivityKeyReps, sessionID: UUID) {
        let clipSource = trackingService.clips
        let repository = repository

        Task(priority: .utility) {
            do {
                try await repository.saveKeyReps(keyReps, sessionID: sessionID)
            } catch {
                LogManager.shared.error("Key repetition save failed", error: error, category: .session)
            }

            guard let group = keyReps.clipGroup else {
                return
            }

            let clips = await clipSource.take(group: group)

            guard !clips.isEmpty else {
                return
            }

            do {
                try await repository.saveRepClips(clips, for: keyReps, sessionID: sessionID)
            } catch {
                LogManager.shared.error("Key repetition clip save failed", error: error, category: .session)
            }
        }
    }
}

// MARK: - Demonstration step

extension BalanceSessionViewModel {
    /// With both arms chosen, the demonstration mirrors to follow the active arm. Highlight and
    /// chime that switch, after the frame's own cue has started so the chime sits beneath it.
    fileprivate func updateDemoArm(from previous: BalanceSnapshot) {
        guard previous.activeArm != snapshot.activeArm,
              !paused,
              !cameraWaiting else {
            return
        }

        demoRevision += 1
        audioService.play(id: UUID(), cue: .demoChanged)
    }
}
