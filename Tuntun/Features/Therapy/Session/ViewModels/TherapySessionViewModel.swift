//
//  TherapySessionViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Combine
import Foundation
import Observation
import UIKit

@MainActor
protocol TherapySessionViewModelProtocol: AnyObject, Observable {
    var sessionLanguage: AppLanguage { get }
    var sessionLocale: Locale { get }
    var snapshot: SessionSnapshot { get }
    var livePose: LivePose.Skeleton? { get }
    var towelDisplay: TowelSnapshot? { get }
    var towelInterpolates: Bool { get }
    var cameraDenied: Bool { get }
    var failure: String? { get }
    var saveFailure: String? { get }
    var saving: Bool { get }
    var voiceReady: Bool { get }
    var listening: Bool { get }
    var demoRevision: Int { get }
    var demoPlayback: TherapyAnimationPlayback { get }
    var demoTitleKey: String { get }
    var elapsedSeconds: Int { get }
    var entryFailure: Bool { get }
    var entryMessage: String { get }
    var validating: Bool { get }
    var isStarting: Bool { get }
    /// The capture owner the camera preview attaches to.
    var trackingService: BodyTrackingService { get }

    func start(permissionService: any PermissionServiceProtocol) async
    func enableVoice(permissionService: any PermissionServiceProtocol) async
    func retryCamera(permissionService: any PermissionServiceProtocol) async
    func openSettings()
    func command(_ command: SessionCommand)
    func readingChanged(_ id: UUID, complete: Bool)
    func previewReady(_ ready: Bool)
    func viewport(width: Double, height: Double)
    func orientationChanged(right: Bool)
    func background()
    func foreground()
    func exit()
    func retrySave()
    func acknowledgeSaveFailure()
}

@MainActor
@Observable
final class TherapySessionViewModel: TherapySessionViewModelProtocol {
    let sessionLanguage = AppLanguage.selected
    var sessionLocale: Locale { sessionLanguage.locale }
    private(set) var snapshot: SessionSnapshot
    /// Practice time shown on the pause dialog. It runs while the session is live and stops
    /// for explicit pauses, camera waits and the summary.
    @ObservationIgnored private var clock = SessionDurationClock()
    private(set) var towelDisplay: TowelSnapshot?
    private(set) var towelInterpolates = false
    @ObservationIgnored private var towelSmoother = TowelPresentationSmoother()
    private(set) var personVisible = false
    /// The tracked skeleton from the first camera frame, shown until the activity draws its guide.
    private(set) var livePose: LivePose.Skeleton?
    @ObservationIgnored private var livePoseTracker = LivePose()
    private(set) var cameraDenied = false
    private(set) var failure: String?
    private(set) var saveFailure: String?
    private(set) var voiceReady = false
    private(set) var listening = false
    /// Increases each time the live demonstration moves to a new step, so the screen can highlight it.
    private(set) var demoRevision = 0
    /// The last example step the live screen has shown, pulsed or accepted silently.
    @ObservationIgnored fileprivate var announcedDemoStep: DemoStep?

    @ObservationIgnored let trackingService: BodyTrackingService
    @ObservationIgnored private let audioService: SessionAudioService
    @ObservationIgnored private let repository: any SessionRepository
    @ObservationIgnored private var engine = SessionEngine()
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var timer: AnyCancellable?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var live = false
    @ObservationIgnored private var permissionService: (any PermissionServiceProtocol)?
    private(set) var entryFailure = false
    private(set) var entryMessage = "home.entryBlocked"
    private(set) var validating = false

    /// True until the first `start` has validated entry and begun capture. Startup is not a failure,
    /// so the view shows a neutral waiting surface instead of recovery controls.
    var isStarting: Bool { !started && !entryFailure }
    @ObservationIgnored private var exited = false
    @ObservationIgnored private var lastPermissionCheck = 0.0
    @ObservationIgnored private var pendingSaves: [SessionEffect] = []
    private(set) var saving = false
    @ObservationIgnored private var keepAwakeBeforeSession = false
    @ObservationIgnored private var recovered = false
    @ObservationIgnored private var allowUnreliableHistory = false
    /// Read once at session start, so a settings change never affects a running session.
    @ObservationIgnored private var replayRecording = ReplayRecording.off

    init(
        trackingService: BodyTrackingService, audioService: SessionAudioService, repository: any SessionRepository, routine: Routine
    ) {
        self.trackingService = trackingService
        self.audioService = audioService
        self.repository = repository
        engine = SessionEngine(routine: routine, scriptedArmRaise: AppLanguage.selected == .indonesian)
        snapshot = engine.snapshot
    }

    #if DEBUG
    /// Detached renderer input for Xcode previews; never enters or runs a session.
    static func presentationFixture(_ snapshot: SessionSnapshot) -> TherapySessionViewModel {
        let model = TherapySessionViewModel(
            trackingService: BodyTrackingService(),
            audioService: SessionAudioService(),
            repository: PresentationFixtureRepository(),
            routine: .demo()
        )
        model.snapshot = snapshot
        model.voiceReady = true
        model.listening = true
        model.started = true
        return model
    }
    #endif

    func start(permissionService: any PermissionServiceProtocol) async {
        guard !started else {
            return
        }
        guard !validating, !exited else { return }
        validating = true
        defer { validating = false }
        self.permissionService = permissionService
        do {
            try await repository.recoverInterrupted()
            recovered = true
        } catch {
            entryMessage = "session.recoveryError"
            entryFailure = true
            return
        }
        guard !exited else { return }
        permissionService.refresh()
        audioService.prepare()
        guard allPermissionsGranted, await audioService.startListening() == .started else {
            audioService.stop()
            entryMessage = "home.entryBlocked"
            entryFailure = true
            return
        }
        guard !exited, !isBackgrounded, !Task.isCancelled else { return }
        entryFailure = false
        voiceReady = true
        listening = true
        started = true
        live = true
        keepAwakeBeforeSession = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        replayRecording = PracticePreferences.replayRecordingLevel
        trackingService.clips.reset()
        trackingService.clips.configure(privacy: PracticePreferences.repClipPrivacy)
        trackingService.frames.sink { [weak self] frame in
            guard let self, self.live else {
                return
            }
            // Observation notifies on every assignment, so unchanged values are not written back.
            let visible = frame.personCount == 1
            if self.personVisible != visible {
                self.personVisible = visible
            }

            // The tracker sees every frame so its smoother stays warm, but the skeleton is published
            // only while it is drawn, before the activity shows its own guide.
            // Mirrors the camera view, which prefers the guide only during the activity stage.
            let skeleton = self.livePoseTracker.skeleton(for: frame)
            let guideShown = self.snapshot.stage == .activity && self.snapshot.presentation?.guide != nil
            if !guideShown {
                self.livePose = skeleton
            } else if self.livePose != nil {
                self.livePose = nil
            }

            var observation = frame
            observation.workspaceMirrored = true
            self.send(.observation(observation))
        }.store(in: &subscriptions)
        trackingService.failures.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self else { return }
            let explanation = String(localized: "session.captureError", bundle: self.sessionLanguage.resourceBundle, locale: self.sessionLocale)
            self.failure = error.isEmpty ? explanation : explanation + "\n" + error
            self.send(.availability(.waiting))
        }.store(in: &subscriptions)
        trackingService.availability.receive(on: DispatchQueue.main).sink { [weak self] availability in
            guard let self else { return }

            switch availability {
            case .ready:
                break
            case .waiting, .discontinuity:
                self.clearLivePose()
            }
            self.send(.availability(availability))
        }.store(in: &subscriptions)
        audioService.events.sink { [weak self] event in self?.receive(event) }.store(in: &subscriptions)
        send(.command(.pause))
        timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink {
            [weak self] _ in self?.send(.tick(ProcessInfo.processInfo.systemUptime))
        }
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first { $0 == .landscapeLeft || $0 == .landscapeRight }
        updateHandRequirement()
        trackingService.configure(landscapeRight: orientation == .landscapeRight)
        trackingService.start()
        send(.command(.resume))
    }

    /// Hand inference runs only for towel folding, which needs the exercised hand to pick the patient's
    /// hand when a bystander's is also visible.
    private func updateHandRequirement() {
        guard let activity = snapshot.activity, activity.kind == .foldTowel else {
            trackingService.requireHand(false)
            return
        }

        trackingService.requireHand(true, side: HandSide(rawValue: activity.side.rawValue))
    }

    private var allPermissionsGranted: Bool {
        guard let permissionService else { return false }
        return AppPermission.allCases.allSatisfy {
            permissionService.status(for: $0) == .authorized
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func retryCamera(permissionService: any PermissionServiceProtocol) async {
        await enableVoice(permissionService: permissionService)
    }

    func enableVoice(permissionService: any PermissionServiceProtocol) async {
        guard live else {
            await start(permissionService: permissionService)
            return
        }
        permissionService.refresh()
        guard allPermissionsGranted else {
            blockReadiness()
            return
        }
        voiceReady = await audioService.startListening() == .started
        guard live, !exited, !isBackgrounded else { return }
        if voiceReady {
            cameraDenied = false
            failure = nil
            trackingService.start()
        }
        // Recovery restores controls only; Resume remains a separate user action.
    }

    private func blockReadiness() {
        voiceReady = false
        listening = false
        cameraDenied = permissionService?.status(for: .camera) != .authorized
        command(.pause)
        trackingService.stop()
        audioService.stop()
    }

    func command(_ command: SessionCommand) {
        switch command {
        case .pause, .stop:
            break
        default:
            guard voiceReady, allPermissionsGranted else { return }
        }
        if case .resume = command {
            permissionService?.refresh()
            guard allPermissionsGranted, voiceReady, listening,
                audioService.capability() == .ready,
                saveFailure == nil || allowUnreliableHistory
            else {
                return
            }
        }
        guard started else { return }
        send(.command(command))
    }

    func readingChanged(_ id: UUID, complete: Bool) {
        send(.readingChanged(id, complete))
    }

    func previewReady(_ ready: Bool) { send(.previewReady(ready)) }
    func viewport(width: Double, height: Double) {
        send(.viewport(TherapyViewport(width: width, height: height)))
    }

    func orientationChanged(right: Bool) {
        trackingService.configure(landscapeRight: right)
    }

    private var isBackgrounded = false

    func background() {
        isBackgrounded = true
        audioService.stop()
        guard live else {
            return
        }
        command(.pause)
        send(.availability(.discontinuity))
        voiceReady = false
        trackingService.stop()
        clearLivePose()
        audioService.stop()
    }

    func foreground() {
        isBackgrounded = false
        Task { await restoreForeground() }
    }

    private func restoreForeground() async {
        guard live else { return }
        permissionService?.refresh()
        guard allPermissionsGranted else {
            blockReadiness()
            return
        }
        voiceReady = await audioService.startListening() == .started
        guard live, !exited, !isBackgrounded else { return }
        if voiceReady { trackingService.start() }
    }

    func exit() {
        exited = true
        if snapshot.summary == nil { command(.stop) }
        cleanup()
        audioService.stop()
    }

    func retrySave() {
        saveFailure = nil
        drainSaves()
    }

    func acknowledgeSaveFailure() {
        allowUnreliableHistory = true
        saveFailure = nil
    }

    private func receive(_ event: AudioEvent) {
        guard live else {
            return
        }
        switch event {
        case .cancelled:
            break
        case .feedbackUnavailable:
            failure = String(localized: "parity.audioUnavailable", bundle: sessionLanguage.resourceBundle, locale: sessionLocale)
        case .completed(let id, let available): send(.guidanceCompleted(id, available))
        case .command(let command):
            switch command {
            case .pause: self.command(.pause)
            case .resume: self.command(.resume)
            }
        case .interrupted: blockReadiness()
        case .voiceUnavailable:
            blockReadiness()
        case .listening(let enabled):
            listening = enabled
            voiceReady = enabled
        }
    }

    private func send(_ event: SessionEvent) {
        guard live else {
            return
        }
        if case .tick(let now) = event, now - lastPermissionCheck >= 0.5 {
            lastPermissionCheck = now
            permissionService?.refresh()
            if !allPermissionsGranted {
                if voiceReady || listening { blockReadiness() }
                return
            }
        }
        let transition = engine.handle(event, at: ProcessInfo.processInfo.systemUptime)
        let previousKind = snapshot.activity?.kind
        let previousSide = snapshot.activity?.side
        let wasPaused = snapshot.paused
        snapshot = transition.snapshot
        updateClock()
        if snapshot.summary != nil {
            audioService.stopMusic()
        } else if wasPaused != snapshot.paused {
            if snapshot.paused {
                audioService.pauseMusic()
            } else if live {
                audioService.resumeMusic()
            }
        }
        towelInterpolates = false
        if snapshot.paused || snapshot.cameraWaiting || snapshot.stage != .activity {
            towelSmoother.reset()
            towelDisplay = nil
        } else if case .observation(let frame) = event,
                  case .towel(let raw) = snapshot.presentation {
            towelDisplay = towelSmoother.consume(raw, time: frame.timestamp, generation: frame.generation)
            towelInterpolates = towelSmoother.interpolates
        } else if case .towel(let raw) = snapshot.presentation {
            towelSmoother.reset()
            towelDisplay = raw
        }
        if previousKind != snapshot.activity?.kind || previousSide != snapshot.activity?.side {
            updateHandRequirement()
        }
        for effect in transition.effects {
            switch effect {
            case .speak(let id, let key):
                var text = Int(key).map(String.init)
                    ?? NarrationText.resolve(key, bundle: sessionLanguage.resourceBundle, locale: sessionLocale)
                if key == "session.guidance", let activity = snapshot.activity {
                    let kindKey = activity.kind.titleKey
                    let sideKey = activity.side == .left ? "session.left" : "session.right"
                    let kindText = String(localized: String.LocalizationValue(kindKey), bundle: sessionLanguage.resourceBundle, locale: sessionLocale)
                    let sideText = String(localized: String.LocalizationValue(sideKey), bundle: sessionLanguage.resourceBundle, locale: sessionLocale)
                    // Spoken short: the exercise and side only; the screen keeps the full sentence.
                    text = activity.hasSide ? kindText + ". " + sideText + "." : kindText + "."
                }
                // A single-key sentence can use its bundled recording; numbers and the
                // combined exercise/side/guidance cue keep the system voice.
                if Int(key) == nil && key != "session.guidance" {
                    audioService.speak(id: id, key: key)
                } else {
                    audioService.speak(id: id, text: text)
                }
            case .audio(let id, let cue): audioService.play(id: id, cue: cue)
            case .cancelSpeech: audioService.cancelSpeech()
            case .keepRepClip(let request):
                trackingService.clips.keep(
                    group: request.group,
                    repNumber: request.repNumber,
                    from: request.start,
                    to: request.end,
                    retaining: request.retaining
                )
            case .checkpoint, .finalize, .saveKeyReps: pendingSaves.append(effect)
            }
        }
        // After the effects, so the clip of a repetition credited by this transition is kept
        // before recording stops for the set's end.
        updateClipRecording()
        // After the effects, so the chime starts beneath the new step's narration instead of
        // being faded out by it.
        updateDemoStep()
        drainSaves()
        if snapshot.summary != nil { cleanup(preserveClosing: true) }
    }

    private func drainSaves() {
        guard !saving, saveFailure == nil, !pendingSaves.isEmpty else {
            return
        }
        saving = true
        Task {
            do {
                if !recovered {
                    try await repository.recoverInterrupted()
                    recovered = true
                }
                while let effect = pendingSaves.first {
                    switch effect {
                    case .checkpoint(let checkpoint): try await repository.checkpoint(checkpoint)
                    case .finalize(let summary): try await repository.finalize(summary)
                    case .saveKeyReps(let sessionID, let keyReps):
                        // The repetition numbers are already in the result; the caregiver's
                        // privacy level decides whether the replay itself is kept.
                        guard replayRecording.savesSkeletons else {
                            break
                        }

                        saveReplayInBackground(for: keyReps, sessionID: sessionID)
                    default: break
                    }
                    pendingSaves.removeFirst()
                }
            } catch {
                saveFailure = error.localizedDescription
                if live { command(.pause) }
            }
            saving = false
        }
    }

    // MARK: - Key-repetition clips

    /// Clip frames are taken only while the patient can be credited with work, never during
    /// pauses, camera waits, stage pages or after the summary.
    private func updateClipRecording() {
        let recording = replayRecording.savesClips
            && live
            && snapshot.stage == .activity
            && !snapshot.paused
            && !snapshot.cameraWaiting
            && snapshot.summary == nil
            && snapshot.activity?.kind.recordsMovement == true

        trackingService.clips.setEnabled(recording)
    }

    /// Replays help review but are not session history: a failed save is only logged and never
    /// pauses therapy or blocks later saves.
    ///
    /// Rewriting the skeleton file and encoding a long set's clips take time, so both run beside
    /// the save queue instead of in it: the summary is finalized, and the plan moves on, without
    /// waiting for them. Each `saveKeyReps` is one actor call, so sets saved together never
    /// interleave.
    private func saveReplayInBackground(for keyReps: ActivityKeyReps, sessionID: UUID) {
        let clipSource = trackingService.clips
        let repository = repository

        Task(priority: .utility) {
            do {
                try await repository.saveKeyReps(keyReps, sessionID: sessionID)
            } catch {
                NSLog("Key repetition save failed: %@", error.localizedDescription)
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
                NSLog("Key repetition clip save failed: %@", String(describing: error))
            }
        }
    }

    private func clearLivePose() {
        livePose = nil
        livePoseTracker.reset()
    }

    private func cleanup(preserveClosing: Bool = false) {
        guard live else {
            return
        }
        live = false
        trackingService.clips.setEnabled(false)
        trackingService.clips.releaseFrames()
        trackingService.stop()
        clearLivePose()
        trackingService.requireHand(false)
        if preserveClosing { audioService.stopListening() } else { audioService.stop() }
        timer?.cancel()
        timer = nil
        subscriptions.removeAll()
        UIApplication.shared.isIdleTimerDisabled = keepAwakeBeforeSession
    }

    // MARK: - Practice clock

    /// Practice time so far, for the pause dialog.
    var elapsedSeconds: Int {
        Int(clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
    }

    private func updateClock() {
        let now = ProcessInfo.processInfo.systemUptime
        let running = !snapshot.paused
            && !snapshot.cameraWaiting
            && snapshot.summary == nil
            && snapshot.stage != .preparing

        if running {
            clock.resume(at: now)
        } else {
            clock.pause(at: now)
        }
    }
}

#if DEBUG
private actor PresentationFixtureRepository: SessionRepository {
    func history() async throws -> [SessionSummary] { [] }
    func unreadableHistoryCount() -> Int { 0 }
    func delete(id: UUID) async throws {}
    func recoverInterrupted() {}
    func checkpoint(_ value: SessionCheckpoint) {}
    func finalize(_ value: SessionSummary) {}
    func saveKeyReps(_ value: ActivityKeyReps, sessionID: UUID) {}
    func keyReps(sessionID: UUID) -> [ActivityKeyReps] { [] }
    func saveRepClips(_ clips: [Int: [RepClipFrame]], for keyReps: ActivityKeyReps, sessionID: UUID) {}
    func repClipURLs(sessionID: UUID) -> [UUID: [Int: URL]] { [:] }
}
#endif

// MARK: - Demonstration step

extension TherapySessionViewModel {
    /// What the arm raise and elbow bend example shows: it loops on the demonstration card and
    /// in practice, and holds the start or peak pose while that pose is being calibrated.
    var demoPlayback: TherapyAnimationPlayback {
        if snapshot.stage == .demonstration {
            return .looping
        }

        guard case .movement(let movement) = snapshot.presentation else {
            return .looping
        }

        switch movement.pose {
        case .start:
            return .staticStart
        case .peak:
            return .staticPeak
        case .looping:
            return .looping
        }
    }

    /// The demonstration column's title, naming the pose the example is holding.
    var demoTitleKey: String {
        guard showsMovementExample else {
            return "session.followMovement"
        }

        switch demoPlayback {
        case .staticStart:
            return "demo.step.start"
        case .staticPeak:
            return "demo.step.peak"
        case .looping:
            return "session.followMovement"
        }
    }

    /// Only arm raise and elbow bend change their example by step; reach and towel keep one.
    private var showsMovementExample: Bool {
        switch snapshot.activity?.kind {
        case .armRaise, .elbowBend:
            return true
        default:
            return false
        }
    }

    /// Highlights and chimes when the live screen shows an example step it has not shown yet.
    ///
    /// Every held start or peak pose pulses as soon as it is visible, even if it first appeared
    /// behind a stage page, since that is when the patient must make a new movement. A looping
    /// step pulses only as a change within the same activity and set (the return to start after
    /// the peak); the first looping step of an activity or set is accepted silently. Nothing is
    /// shown while paused, waiting for the camera or behind a stage page, so a step reached then
    /// pulses once the live screen returns.
    fileprivate func updateDemoStep() {
        guard showsMovementExample, let activity = snapshot.activity else {
            announcedDemoStep = nil
            return
        }

        let watchingLiveScreen = snapshot.stage == .activity
            && !snapshot.paused
            && !snapshot.cameraWaiting

        guard watchingLiveScreen else {
            return
        }

        let step = DemoStep(
            activityID: activity.id,
            setNumber: snapshot.setNumber,
            playback: demoPlayback
        )

        guard step != announcedDemoStep else {
            return
        }

        let previous = announcedDemoStep
        announcedDemoStep = step

        let sameRun = previous?.activityID == step.activityID
            && previous?.setNumber == step.setNumber

        guard step.playback != .looping || sameRun else {
            return
        }

        demoRevision += 1
        audioService.play(id: UUID(), cue: .demoChanged)
    }
}

/// The example's identity for change detection.
fileprivate struct DemoStep: Equatable {
    let activityID: UUID
    let setNumber: Int
    let playback: TherapyAnimationPlayback
}
