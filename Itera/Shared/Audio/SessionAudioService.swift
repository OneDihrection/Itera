//
//  SessionAudioService.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import AVFoundation
import Combine
import Speech
import OSLog

// Audio events are scoped by utterance identity; recognition callbacks have their own generation.
enum AudioEvent {
    case completed(UUID, Bool)
    case cancelled(UUID)
    case command(AudioCommand)
    case interrupted
    case voiceUnavailable
    case listening(Bool)
    case feedbackUnavailable
}

enum VoiceCapability: Equatable {
    case ready
    case unsupported
    case unavailable
}

enum VoiceStartupResult: Equatable {
    case started
    case unsupported
    case unavailable
    case inputFailure
    case permissionDenied
}

@MainActor
protocol VoiceReadinessProviding: AnyObject {
    func prepare()
    func capability() -> VoiceCapability
    func startListening() async -> VoiceStartupResult
    func stop()
}

@MainActor
final class SessionAudioService: NSObject, VoiceReadinessProviding, AVSpeechSynthesizerDelegate, SFSpeechRecognizerDelegate {
    let events = PassthroughSubject<AudioEvent, Never>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Itera", category: "SessionAudio")
    private var routeObserver: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()
    private let music = ExerciseMusicPlayer()
    private var narrationClips: [String: PreparedAudioClip] = [:]
    private let inputWorker = AudioInputWorker()
    private var starting: Task<VoiceStartupResult, Never>?
    private var listeningActive = false
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionGeneration = UUID()
    private var utteranceIDs: [ObjectIdentifier: UUID] = [:]
    private var interruption: NSObjectProtocol?
    private var consumed = false
    private var language = AppLanguage.selected
    // Command recognition stays English independently of narration language.
    private let recognitionLocale = Locale(identifier: "en-US")
    private var synthesisLocale = "en-US"
    private var voice: AVSpeechSynthesisVoice?
    private var clips: [String: PreparedAudioClip] = [:]
    private var targetEffect: PreparedAudioClip?
    private var towelEffects: [String: PreparedAudioClip] = [:]
    private var activeClip: PreparedAudioClip?
    private var clipID: UUID?
    private var clipWatchdog: Task<Void, Never>?
    private var afterClip: (() -> Void)?
    private var failedClip: (() -> Void)?
    private var pendingSpeech: (id: UUID, text: String, key: String?)?
    private var pendingCounts: [(id: UUID, number: Int)] = []
    private var speechWatchdog: Task<Void, Never>?
    private var closingWatchdog: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.logAudioConfiguration("route changed") }
        }
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                type == AVAudioSession.InterruptionType.began.rawValue
            else {
                return
            }
            Task { @MainActor in
                self?.music.pause()
                self?.events.send(.interrupted)
            }
        }
    }

    deinit {
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    func prepare() {
        language = AppLanguage.selected
        synthesisLocale = language.speechIdentifier
        voice = NarrationVoice.best(for: synthesisLocale)
        clips = [:]
        towelEffects = [:]
        for name in ["button-click", "target-reached", "set-complete"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
                towelEffects[name] = try? PreparedAudioClip(url: url)
            }
        }
        if let url = Bundle.main.url(forResource: "target-reached", withExtension: "wav") {
            targetEffect = try? PreparedAudioClip(url: url)
        }
    }

    func speak(id: UUID, text: String) {
        if !utteranceIDs.isEmpty || clipID != nil {
            if let previous = pendingSpeech { events.send(.cancelled(previous.id)) }
            pendingSpeech = (id, text, nil)
            return
        }
        guard let voice else {
            // Defer failure so callers finish applying the transition before recovery.
            Task { @MainActor [weak self] in
                self?.events.send(.feedbackUnavailable)
                self?.events.send(.completed(id, false))
                self?.drainPendingAudio()
            }
            return
        }
        let utterance = NarrationVoice.utterance(text, voice: voice)
        utteranceIDs[ObjectIdentifier(utterance)] = id
        music.setDucked(true)
        synthesizer.speak(utterance)
        speechWatchdog?.cancel()
        speechWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.utteranceIDs.values.contains(id) else { return }
            self.utteranceIDs.removeAll()
            self.music.setDucked(false)
            self.synthesizer.stopSpeaking(at: .immediate)
            self.events.send(.feedbackUnavailable)
            self.events.send(.completed(id, false))
            self.drainPendingAudio()
        }
    }

    func cancelSpeech() {
        let cancelled = Array(utteranceIDs.values) + [clipID, pendingSpeech?.id].compactMap { $0 }
            + pendingCounts.map(\.id)
        pendingSpeech = nil
        pendingCounts.removeAll(keepingCapacity: true)
        speechWatchdog?.cancel()
        speechWatchdog = nil
        targetEffect?.stop()
        towelEffects.values.forEach { $0.stop() }
        clipID = nil
        clipWatchdog?.cancel()
        clipWatchdog = nil
        afterClip = nil
        failedClip = nil
        activeClip?.stop()
        activeClip = nil
        closingWatchdog?.cancel()
        closingWatchdog = nil
        utteranceIDs.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        music.setDucked(false)
        for id in cancelled { events.send(.cancelled(id)) }
    }

    private func prepareClip(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        clips[name] = try? PreparedAudioClip(url: url)
    }

    func play(id: UUID, cue: SessionAudioCue) {
        switch cue {
        case .towelGrab, .towelFold, .towelCompleted:
            guard UserDefaults.standard.object(forKey: PracticePreferences.celebrationSounds) as? Bool ?? true else {
                return
            }
            let name: String
            switch cue {
            case .towelGrab: name = "button-click"
            case .towelFold: name = "target-reached"
            default: name = "set-complete"
            }
            towelEffects.values.forEach { $0.stop() }
            let volume: Float = utteranceIDs.isEmpty && clipID == nil ? 0.65 : 0.26
            guard let player = towelEffects[name],
                  player.play(id: id, volume: volume, completion: { [weak self] _, success in
                      if !success { self?.events.send(.feedbackUnavailable) }
                  }) else {
                events.send(.feedbackUnavailable)
                return
            }
        case .target:
            let volume: Float = utteranceIDs.isEmpty && clipID == nil ? 1 : 0.4
            guard let targetEffect,
                  targetEffect.play(id: id, volume: volume, completion: { [weak self] _, success in
                      if !success { self?.events.send(.feedbackUnavailable) }
                  }) else {
                events.send(.feedbackUnavailable)
                return
            }
        case .count(let number):
            if !utteranceIDs.isEmpty || clipID != nil {
                guard pendingCounts.count < 32 else {
                    events.send(.feedbackUnavailable)
                    return
                }
                pendingCounts.append((id, number))
                return
            }
            let language = synthesisLocale.hasPrefix("id") ? "id" : "en"
            let name = "count-\(language)-\(number)"
            if Bundle.main.url(forResource: name, withExtension: "wav") != nil {
                playClip(name, id: id, timeout: 20, failure: { [weak self] in
                    self?.speak(id: id, text: String(number))
                })
            } else {
                speak(id: id, text: String(number))
            }
        case .countdown(let number):
            // Countdown time is authoritative; never queue an expired number.
            cancelSpeech()
            let language = synthesisLocale.hasPrefix("id") ? "id" : "en"
            let name = "count-\(language)-\(number)"
            if Bundle.main.url(forResource: name, withExtension: "wav") != nil {
                playClip(name, id: id, timeout: 1, failure: { [weak self] in
                    self?.speak(id: id, text: String(number))
                })
            } else {
                speak(id: id, text: String(number))
            }
        case .guidance(let prefix, let key):
            cancelSpeech()
            let name: String
            let timeout: Double
            switch prefix {
            case .target:
                name = "target-reached"
                timeout = 1
            case .count(let number):
                let language = synthesisLocale.hasPrefix("id") ? "id" : "en"
                name = "count-\(language)-\(number)"
                timeout = 20
            default:
                // Recorded Marizka narration when bundled, otherwise the system voice.
                speak(id: id, key: key)
                return
            }
            playClip(name, id: id, timeout: timeout, completion: { [weak self] in
                self?.speak(id: id, key: key)
            })
        case .closing(let completed):
            cancelSpeech()
            let key = completed ? "parity.closingComplete" : "parity.closingPartial"
            let speakClosing = { [weak self] in
                guard let self else { return }
                self.speak(id: id, key: key)
                self.closingWatchdog = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    self?.cancelSpeech()
                }
            }
            if completed {
                playClip("closing-chime", id: id, timeout: 1.5, completion: speakClosing)
            } else {
                speakClosing()
            }
        }
    }

    func speak(id: UUID, key: String) {
        let text = String(localized: String.LocalizationValue(key), bundle: language.resourceBundle, locale: language.locale)
        guard utteranceIDs.isEmpty, clipID == nil else {
            if let previous = pendingSpeech {
                events.send(.cancelled(previous.id))
            }
            pendingSpeech = (id, text, key)
            return
        }
        let line = NarrationLine(key: key)
        let name = NarrationClips.resourceName(for: line)
        if narrationClips[name] == nil, let url = NarrationClips.url(for: line, language: language) {
            narrationClips[name] = try? PreparedAudioClip(url: url)
        }
        guard let clip = narrationClips[name] else {
            speak(id: id, text: text)
            return
        }
        activeClip = clip
        clipID = id
        music.setDucked(true)
        let completed: (UUID, Bool) -> Void = { [weak self] id, success in
            guard let self, self.clipID == id else { return }
            self.clipID = nil
            self.activeClip?.stop()
            self.activeClip = nil
            self.clipWatchdog?.cancel()
            self.clipWatchdog = nil
            self.music.setDucked(false)
            if success {
                self.events.send(.completed(id, true))
                self.drainPendingAudio()
            } else {
                self.speak(id: id, text: text)
            }
        }
        guard clip.play(id: id, completion: completed) else {
            completed(id, false)
            return
        }
        clipWatchdog = Task {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            completed(id, false)
        }
    }

    private func playClip(_ name: String, id: UUID, timeout: Double, failure: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        clips.removeAll()
        prepareClip(name)
        guard let clip = clips[name] else {
            events.send(.feedbackUnavailable)
            failure?()
            completion?()
            drainPendingAudio()
            return
        }
        activeClip = clip
        music.setDucked(true)
        clipID = id
        afterClip = completion
        failedClip = failure
        guard clip.play(id: id, completion: { [weak self] id, success in
            self?.finishClip(id, success: success)
        }) else {
            finishClip(id, success: false)
            return
        }
        clipWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            self?.finishClip(id, success: false)
        }
    }

    private func finishClip(_ id: UUID, success: Bool) {
        guard clipID == id else { return }
        let completion = afterClip
        let failure = failedClip
        failedClip = nil
        clipID = nil
        afterClip = nil
        clipWatchdog?.cancel()
        clipWatchdog = nil
        activeClip?.stop()
        activeClip = nil
        music.setDucked(false)
        if !success {
            events.send(.feedbackUnavailable)
            failure?()
        }
        completion?()
        drainPendingAudio()
    }

    private func drainPendingAudio() {
        guard utteranceIDs.isEmpty, clipID == nil else { return }
        if !pendingCounts.isEmpty {
            let next = pendingCounts.removeFirst()
            play(id: next.id, cue: .count(next.number))
        } else if let next = pendingSpeech {
            pendingSpeech = nil
            if let key = next.key {
                speak(id: next.id, key: key)
            } else {
                speak(id: next.id, text: next.text)
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                let id = self.utteranceIDs.removeValue(forKey: ObjectIdentifier(utterance))
            else {
                return
            }
            self.speechWatchdog?.cancel()
            self.speechWatchdog = nil
            self.music.setDucked(false)
            self.events.send(.completed(id, true))
            self.drainPendingAudio()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  let id = self.utteranceIDs.removeValue(forKey: ObjectIdentifier(utterance)) else { return }
            self.speechWatchdog?.cancel()
            self.speechWatchdog = nil
            self.music.setDucked(false)
            self.events.send(.feedbackUnavailable)
            self.events.send(.completed(id, false))
            self.drainPendingAudio()
        }
    }

    func capability() -> VoiceCapability {
        guard let recognizer = SFSpeechRecognizer(locale: recognitionLocale),
            recognizer.supportsOnDeviceRecognition
        else {
            return .unsupported
        }
        return recognizer.isAvailable ? .ready : .unavailable
    }

    @discardableResult
    func startListening() async -> VoiceStartupResult {
        if listeningActive { return .started }
        if let starting { return await starting.value }
        let generation = UUID()
        recognitionGeneration = generation
        let task = Task { await self.activateListening(generation: generation) }
        starting = task
        return await task.value
    }

    private func activateListening(generation: UUID) async -> VoiceStartupResult {
        guard recognitionGeneration == generation, !Task.isCancelled else { return .unavailable }
        defer {
            if recognitionGeneration == generation || listeningActive { starting = nil }
        }
        guard AVAudioApplication.shared.recordPermission == .granted,
            SFSpeechRecognizer.authorizationStatus() == .authorized
        else {
            events.send(.voiceUnavailable)
            return .permissionDenied
        }
        let readiness = capability()
        guard readiness == .ready,
            let recognizer = SFSpeechRecognizer(locale: recognitionLocale)
        else {
            events.send(.voiceUnavailable)
            return readiness == .unsupported ? .unsupported : .unavailable
        }
        self.recognizer = recognizer
        recognizer.delegate = self
        consumed = false
        let success = await inputWorker.start()
        guard recognitionGeneration == generation else { return .unavailable }
        starting = nil
        guard success, !Task.isCancelled else {
            stopListening()
            events.send(.voiceUnavailable)
            return .inputFailure
        }
        listeningActive = true
        beginUtterance(recognizer)
        logAudioConfiguration("listening started")
        events.send(.listening(true))
        return .started
    }

    private func beginUtterance(_ recognizer: SFSpeechRecognizer) {
        let generation = UUID()
        recognitionGeneration = generation
        inputWorker.replaceRequest(nil)
        recognition?.cancel()
        request?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        consumed = false
        inputWorker.replaceRequest(request)
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.recognitionGeneration == generation else {
                    return
                }
                if let result, !self.consumed {
                    let words = result.bestTranscription.formattedString.lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // Exact short utterances avoid substring triggers from app narration.
                    if let command = self.command(words) {
                        self.consumed = true
                        self.events.send(.command(command))
                        // Begin a fresh utterance after a command so the next command can interrupt it.
                        if self.recognitionGeneration == generation {
                            self.beginUtterance(recognizer)
                        }
                        return
                    }
                }
                if result?.isFinal == true || error != nil {
                    if error != nil {
                        self.stopListening()
                        self.events.send(.voiceUnavailable)
                    } else {
                        self.beginUtterance(recognizer)
                    }
                }
            }
        }
    }

    nonisolated func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool
    ) {
        guard !available else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.recognizer === speechRecognizer else {
                return
            }
            self.stopListening()
            self.events.send(.voiceUnavailable)
        }
    }

    private var commandBundle: Bundle {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    private func command(_ words: String) -> AudioCommand? {
        let keys: [(String, AudioCommand)] = [
            ("command.stop", .stop), ("command.pause", .pause), ("command.resume", .resume),
            ("command.skip", .skip), ("command.repeat", .repeatInstruction), ("command.recalibrate", .retryCalibration),
            ("command.help", .help), ("command.redo", .redo),
            ("command.adjustTarget", .adjustTarget), ("command.retryStep", .retryStep),
            ("command.skipStep", .skipStep), ("command.timedPractice", .timedPractice),
        ]
        return keys.first {
            String(localized: String.LocalizationValue($0.0), bundle: commandBundle).lowercased() == words
        }?.1
    }

    /// Logs configuration only; never logs recognized words or microphone samples.
    private func logAudioConfiguration(_ context: String) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        logger.notice("Audio \(context, privacy: .public): category=\(session.category.rawValue, privacy: .public) mode=\(session.mode.rawValue, privacy: .public) outputs=\(outputs, privacy: .public) systemVolume=\(session.outputVolume)")
    }

    func stopListening() {
        inputWorker.replaceRequest(nil)
        recognitionGeneration = UUID()
        recognizer?.delegate = nil
        recognizer = nil
        recognition?.cancel()
        recognition = nil
        request?.endAudio()
        request = nil
        listeningActive = false
        starting?.cancel()
        starting = nil
        inputWorker.stop()
        events.send(.listening(false))
    }

    func startMusic() {
        do {
            try NarrationAudioSession.activate(listening: listeningActive)
            music.start()
        } catch {
            music.pause()
        }
    }

    func pauseMusic() { music.pause() }
    func resumeMusic() { startMusic() }
    func stopMusic() { music.stop() }

    func stop() {
        music.stop()
        cancelSpeech()
        stopListening()
        inputWorker.stop(deactivate: true)
    }

    private enum AudioFailure: Error { case inputUnavailable }
}
