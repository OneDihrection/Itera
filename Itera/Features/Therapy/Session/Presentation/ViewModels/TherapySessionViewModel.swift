//
//  TherapySessionViewModel.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Combine
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class TherapySessionViewModel {
    let sessionLanguage = AppLanguage.selected
    var sessionLocale: Locale { sessionLanguage.locale }
    private(set) var snapshot = SessionSnapshot()
    private(set) var personVisible = false
    private(set) var cameraDenied = false
    private(set) var failure: String?
    private(set) var saveFailure: String?
    private(set) var voiceReady = false
    private(set) var listening = false
    private(set) var frontCamera = true

    @ObservationIgnored let tracking: BodyTrackingService
    @ObservationIgnored private let audio: SessionAudioService
    @ObservationIgnored private let repository: any SessionRepository
    @ObservationIgnored private var engine = SessionEngine()
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var timer: AnyCancellable?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var live = false
    @ObservationIgnored private var permissions: (any PermissionManaging)?
    private(set) var entryFailure = false
    private(set) var entryMessage = "home.entryBlocked"
    private(set) var validating = false
    @ObservationIgnored private var exited = false
    @ObservationIgnored private var lastPermissionCheck = 0.0
    @ObservationIgnored private var landscapeRight = false
    @ObservationIgnored private var pendingSaves: [SessionEffect] = []
    private(set) var saving = false
    @ObservationIgnored private var keepAwakeBeforeSession = false
    @ObservationIgnored private var recovered = false
    @ObservationIgnored private var allowUnreliableHistory = false

    init(
        tracking: BodyTrackingService, audio: SessionAudioService, repository: any SessionRepository, routine: Routine
    ) {
        self.tracking = tracking
        self.audio = audio
        self.repository = repository
        engine = SessionEngine(routine: routine)
    }

    #if DEBUG
    /// Detached renderer input for Xcode previews; never enters or runs a session.
    static func presentationFixture(_ snapshot: SessionSnapshot) -> TherapySessionViewModel {
        let model = TherapySessionViewModel(
            tracking: BodyTrackingService(),
            audio: SessionAudioService(),
            repository: PresentationFixtureRepository(),
            routine: .demo()
        )
        model.snapshot = snapshot
        model.voiceReady = true
        model.listening = true
        return model
    }
    #endif

    func start(permissions: any PermissionManaging) async {
        guard !started else {
            return
        }
        guard !validating, !exited else { return }
        validating = true
        defer { validating = false }
        self.permissions = permissions
        do {
            try await repository.recoverInterrupted()
            recovered = true
        } catch {
            entryMessage = "session.recoveryError"
            entryFailure = true
            return
        }
        guard !exited else { return }
        permissions.refresh()
        audio.prepare()
        guard allPermissionsGranted, audio.startListening() == .started else {
            audio.stop()
            entryMessage = "home.entryBlocked"
            entryFailure = true
            return
        }
        entryFailure = false
        voiceReady = true
        listening = true
        started = true
        live = true
        keepAwakeBeforeSession = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        tracking.frames.sink { [weak self] frame in
            guard let self, self.live else {
                return
            }
            self.personVisible = frame.personCount == 1
            self.send(.observation(frame))
        }.store(in: &subscriptions)
        tracking.cupFailures.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self else { return }
            self.failure = String(localized: String.LocalizationValue(error), bundle: self.sessionLanguage.resourceBundle, locale: self.sessionLocale)
            self.command(.pause)
        }.store(in: &subscriptions)
        tracking.failures.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self else { return }
            let explanation = String(localized: "session.captureError", bundle: self.sessionLanguage.resourceBundle, locale: self.sessionLocale)
            self.failure = error.isEmpty ? explanation : explanation + "\n" + error
            self.send(.availability(.waiting))
        }.store(in: &subscriptions)
        tracking.availability.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.send(.availability($0))
        }.store(in: &subscriptions)
        audio.events.sink { [weak self] event in self?.receive(event) }.store(in: &subscriptions)
        send(.command(.pause))
        timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink {
            [weak self] _ in self?.send(.tick(ProcessInfo.processInfo.systemUptime))
        }
        tracking.start()
        send(.command(.resume))
    }

    private var allPermissionsGranted: Bool {
        guard let permissions else { return false }
        return AppPermission.allCases.allSatisfy {
            permissions.status(for: $0) == .authorized
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func retryCamera(permissions: any PermissionManaging) async {
        await enableVoice(permissions: permissions)
    }

    func enableVoice(permissions: any PermissionManaging) async {
        guard live else {
            await start(permissions: permissions)
            return
        }
        permissions.refresh()
        guard allPermissionsGranted else {
            blockReadiness()
            return
        }
        voiceReady = audio.startListening() == .started
        if voiceReady {
            cameraDenied = false
            failure = nil
            tracking.start()
        }
        // Recovery restores controls only; Resume remains a separate user action.
    }

    private func blockReadiness() {
        voiceReady = false
        listening = false
        cameraDenied = permissions?.status(for: .camera) != .authorized
        command(.pause)
        tracking.stop()
        audio.stop()
    }

    func command(_ command: SessionCommand) {
        switch command {
        case .pause, .stop:
            break
        default:
            guard voiceReady, allPermissionsGranted else { return }
        }
        if case .resume = command {
            permissions?.refresh()
            guard allPermissionsGranted, voiceReady, listening,
                audio.capability() == .ready,
                saveFailure == nil || allowUnreliableHistory
            else {
                return
            }
        }
        guard started else { return }
        if case .retryCalibration = command, snapshot.activity?.kind == .cup {
            failure = nil
            tracking.requireCup(true)
        }
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
        landscapeRight = right
        tracking.configure(front: frontCamera, landscapeRight: right)
    }

    func switchCamera() {
        command(.pause)
        frontCamera.toggle()
        send(.previewReady(false))
        tracking.configure(front: frontCamera, landscapeRight: landscapeRight)
    }

    func background() {
        guard live else {
            return
        }
        command(.pause)
        send(.availability(.discontinuity))
        voiceReady = false
        tracking.stop()
        audio.stop()
    }

    func foreground() {
        guard live else { return }
        permissions?.refresh()
        guard allPermissionsGranted else {
            blockReadiness()
            return
        }
        voiceReady = audio.startListening() == .started
        if voiceReady { tracking.start() }
    }

    func exit() {
        exited = true
        if snapshot.summary == nil { command(.stop) }
        cleanup()
        audio.stop()
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
        case .feedbackUnavailable:
            failure = String(localized: "parity.audioUnavailable", bundle: sessionLanguage.resourceBundle, locale: sessionLocale)
        case .completed(let id, let available): send(.guidanceCompleted(id, available))
        case .command(let command):
            switch command {
            case .pause: self.command(.pause)
            case .resume: self.command(.resume)
            case .stop: self.command(.stop)
            case .repeatInstruction: self.command(.repeatInstruction)
            case .help: self.command(.help)
            case .redo: self.command(.redo)
            case .adjustTarget: self.command(.adjustTarget)
            case .retryStep: self.command(.retryStep)
            case .skipStep: self.command(.skipStep)
            case .timedPractice: self.command(.timedPractice)
            case .retryCalibration: self.command(.retryCalibration)
            case .skip: self.command(.skip)
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
            permissions?.refresh()
            if !allPermissionsGranted {
                if voiceReady || listening { blockReadiness() }
                return
            }
        }
        let transition = engine.handle(event, at: ProcessInfo.processInfo.systemUptime)
        let previousKind = snapshot.activity?.kind
        snapshot = transition.snapshot
        if previousKind != snapshot.activity?.kind {
            tracking.requireCup(snapshot.activity?.kind == .cup)
        }
        for effect in transition.effects {
            switch effect {
            case .speak(let id, let key):
                var text = Int(key).map(String.init) ?? String(localized: String.LocalizationValue(key), bundle: sessionLanguage.resourceBundle, locale: sessionLocale)
                if key == "session.guidance", let activity = snapshot.activity {
                    let kindKey: String
                    switch activity.kind {
                    case .armRaise: kindKey = "session.armRaise"
                    case .elbowBend: kindKey = "session.elbowBend"
                    case .directionalReach: kindKey = "session.directionalReach"
                    case .cup: kindKey = "session.cup"
                    }
                    let sideKey = activity.side == .left ? "session.left" : "session.right"
                    text = String(localized: String.LocalizationValue(kindKey), bundle: sessionLanguage.resourceBundle, locale: sessionLocale) + ". "
                        + String(localized: String.LocalizationValue(sideKey), bundle: sessionLanguage.resourceBundle, locale: sessionLocale) + ". " + text
                }
                audio.speak(id: id, text: text)
            case .audio(let id, let cue): audio.play(id: id, cue: cue)
            case .cancelSpeech: audio.cancelSpeech()
            case .checkpoint, .finalize: pendingSaves.append(effect)
            }
        }
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

    private func cleanup(preserveClosing: Bool = false) {
        guard live else {
            return
        }
        live = false
        tracking.requireCup(false)
        tracking.stop()
        if preserveClosing { audio.stopListening() } else { audio.stop() }
        timer?.cancel()
        timer = nil
        subscriptions.removeAll()
        UIApplication.shared.isIdleTimerDisabled = keepAwakeBeforeSession
    }
}

#if DEBUG
private actor PresentationFixtureRepository: SessionRepository {
    func recoverInterrupted() {}
    func checkpoint(_ value: SessionCheckpoint) {}
    func finalize(_ value: SessionSummary) {}
}
#endif
