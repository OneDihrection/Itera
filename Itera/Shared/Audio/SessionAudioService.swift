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
    func startListening() -> VoiceStartupResult
    func stop()
}

@MainActor
final class SessionAudioService: NSObject, VoiceReadinessProviding, AVSpeechSynthesizerDelegate, SFSpeechRecognizerDelegate {
    let events = PassthroughSubject<AudioEvent, Never>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Itera", category: "SessionAudio")
    private var routeObserver: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()
    private let music = ExerciseMusicPlayer()
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionGeneration = UUID()
    private var recognitionRestartTask: Task<Void, Never>?
    private var utteranceIDs: [ObjectIdentifier: UUID] = [:]
    private var interruption: NSObjectProtocol?
    private var consumed = false
    private var language = AppLanguage.selected
    private var synthesisLocale = "en-US"
    private var voice: AVSpeechSynthesisVoice?
    private var tapInstalled = false
    private var clips: [String: PreparedAudioClip] = [:]
    /// Recorded narration loaded on first use; see `NarrationClips`.
    private var narrationClips: [String: PreparedAudioClip] = [:]
    private var activeClip: PreparedAudioClip?
    private var clipID: UUID?
    private var clipWatchdog: Task<Void, Never>?
    private var afterClip: (() -> Void)?
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
        let language = synthesisLocale.hasPrefix("id") ? "id" : "en"
        for number in 1...100 {
            prepareClip("count-\(language)-\(number)")
        }
        prepareClip("target-reached")
        prepareClip("closing-chime")
    }

    func speak(id: UUID, text: String) {
        cancelSpeech()
        guard let voice else {
            events.send(.completed(id, false))
            return
        }
        let utterance = NarrationVoice.utterance(text, voice: voice)
        utterance.volume = 1
        utteranceIDs[ObjectIdentifier(utterance)] = id
        music.setDucked(true)
        synthesizer.speak(utterance)
    }

    func cancelSpeech() {
        clipID = nil
        clipWatchdog?.cancel()
        clipWatchdog = nil
        afterClip = nil
        activeClip?.stop()
        activeClip = nil
        closingWatchdog?.cancel()
        closingWatchdog = nil
        utteranceIDs.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        music.setDucked(false)
    }

    private func prepareClip(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        clips[name] = try? PreparedAudioClip(url: url)
    }

    func play(id: UUID, cue: SessionAudioCue) {
        switch cue {
        case .target:
            // Ordinary target feedback never interrupts guidance or an accepted count.
            guard utteranceIDs.isEmpty, clipID == nil else { return }
            playClip("target-reached", id: id, timeout: 1)
        case .count(let number):
            cancelSpeech()
            let language = synthesisLocale.hasPrefix("id") ? "id" : "en"
            playClip("count-\(language)-\(number)", id: id, timeout: 20)
        case .countdown(let number):
            speak(id: id, text: String(number))
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
                speak(id: id, key: key)
                return
            }
            playClip(name, id: id, timeout: timeout) { [weak self] in
                self?.speak(id: id, key: key)
            }
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

    // MARK: - Recorded narration

    /// Plays the bundled recording of a String Catalog key, or speaks its text when there is
    /// none or it fails. Completion is reported once, like ordinary speech.
    func speak(id: UUID, key: String) {
        let text = String(localized: String.LocalizationValue(key), bundle: language.resourceBundle, locale: language.locale)

        guard let clip = narrationClip(for: key) else {
            speak(id: id, text: text)
            return
        }

        cancelSpeech()
        activeClip = clip
        music.setDucked(true)
        clipID = id

        let started = clip.play(id: id) { [weak self] id, success in
            guard let self, self.clipID == id else {
                return
            }

            self.clipID = nil
            self.activeClip = nil
            self.music.setDucked(false)
            self.clipWatchdog?.cancel()
            self.clipWatchdog = nil

            if success {
                self.events.send(.completed(id, true))
            } else {
                self.speak(id: id, text: text)
            }
        }

        guard started else {
            clipID = nil
            activeClip = nil
            speak(id: id, text: text)
            return
        }

        // Recordings are a few seconds long; a stalled player falls back to speech.
        clipWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.clipID == id else { return }
            self.speak(id: id, text: text)
        }
    }

    private func narrationClip(for key: String) -> PreparedAudioClip? {
        let line = NarrationLine(key: key)
        let name = NarrationClips.resourceName(for: line)

        if let cached = narrationClips[name] {
            return cached
        }

        guard let url = NarrationClips.url(for: line, language: language),
              let clip = try? PreparedAudioClip(url: url) else {
            return nil
        }

        narrationClips[name] = clip
        return clip
    }

    private func playClip(_ name: String, id: UUID, timeout: Double, completion: (() -> Void)? = nil) {
        guard let clip = clips[name] else {
            events.send(.feedbackUnavailable)
            completion?()
            return
        }
        activeClip = clip
        music.setDucked(true)
        clipID = id
        afterClip = completion
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
        clipID = nil
        afterClip = nil
        clipWatchdog?.cancel()
        clipWatchdog = nil
        activeClip?.stop()
        activeClip = nil
        music.setDucked(false)
        if !success { events.send(.feedbackUnavailable) }
        completion?()
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
            self.music.setDucked(false)
            self.events.send(.completed(id, true))
        }
    }

    func capability() -> VoiceCapability {
        let recognizers = recognitionLocaleIdentifiers.compactMap {
            SFSpeechRecognizer(locale: Locale(identifier: $0))
        }
        guard recognizers.contains(where: \.supportsOnDeviceRecognition) else {
            return .unsupported
        }
        return recognizers.contains {
            $0.supportsOnDeviceRecognition && $0.isAvailable
        } ? .ready : .unavailable
    }

    @discardableResult
    func startListening() -> VoiceStartupResult {
        recognitionRestartTask?.cancel()
        recognitionRestartTask = nil
        tearDownListening(notify: false)
        guard AVAudioApplication.shared.recordPermission == .granted,
            SFSpeechRecognizer.authorizationStatus() == .authorized
        else {
            events.send(.voiceUnavailable)
            return .permissionDenied
        }
        let readiness = capability()
        guard readiness == .ready, let recognizer = preferredRecognizer() else {
            events.send(.voiceUnavailable)
            return readiness == .unsupported ? .unsupported : .unavailable
        }
        self.recognizer = recognizer
        recognizer.delegate = self
        let generation = UUID()
        recognitionGeneration = generation
        consumed = false
        do {
            // Full-volume narration while listening; see NarrationAudioSession for the
            // trade-off and the launch argument that compares against `.voiceChat`.
            try NarrationAudioSession.activate(listening: true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = commandPhrases
            request.taskHint = .confirmation
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioFailure.inputUnavailable }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            logAudioConfiguration("listening started")
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.recognitionGeneration == generation else {
                        return
                    }
                    if let result, !self.consumed {
                        let words = result.bestTranscription.formattedString
                        if let command = self.command(words) {
                            self.consumed = true
                            self.events.send(.command(command))
                            if self.recognitionGeneration == generation {
                                self.scheduleListeningRestart(after: 0.12)
                            }
                            return
                        }
                    }
                    if result?.isFinal == true || error != nil {
                        if self.recognitionGeneration == generation {
                            self.scheduleListeningRestart(after: error == nil ? 0.08 : 0.30)
                        }
                    }
                }
            }
            events.send(.listening(true))
            return .started
        } catch {
            logger.error("Audio startup failed: \(String(describing: error), privacy: .public)")
            stopListening()
            events.send(.voiceUnavailable)
            return .inputFailure
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

    private func command(_ words: String) -> AudioCommand? {
        let normalizedWords = normalizeCommand(words)
        let heardTokens = normalizedWords.split(separator: " ")
        guard heardTokens.count <= 3 else { return nil }
        return commandKeys.first { key, _ in
            commandBundles.contains { bundle in
                let phrase = normalizeCommand(String(
                    localized: String.LocalizationValue(key),
                    bundle: bundle
                ))
                return normalizedWords == phrase
                    || heardTokens.contains(Substring(phrase))
            }
        }?.1
    }

    private var commandKeys: [(String, AudioCommand)] {
        [
            ("command.stop", .stop), ("command.end", .stop), ("command.pause", .pause),
            ("command.start", .resume), ("command.resume", .resume),
            ("command.skip", .skip), ("command.repeat", .repeatInstruction), ("command.recalibrate", .retryCalibration),
            ("command.help", .help), ("command.redo", .redo),
            ("command.adjustTarget", .adjustTarget), ("command.retryStep", .retryStep),
            ("command.skipStep", .skipStep), ("command.timedPractice", .timedPractice),
        ]
    }

    private var commandBundles: [Bundle] {
        ["en", "id"].compactMap { language in
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else {
                return nil
            }
            return Bundle(path: path)
        }
    }

    private var commandPhrases: [String] {
        Array(Set(commandKeys.flatMap { key, _ in
            commandBundles.map {
                String(localized: String.LocalizationValue(key), bundle: $0)
            }
        })).sorted()
    }

    private var recognitionLocaleIdentifiers: [String] {
        language == .indonesian ? ["id-ID", "en-US"] : ["en-US", "id-ID"]
    }

    private func preferredRecognizer() -> SFSpeechRecognizer? {
        recognitionLocaleIdentifiers.lazy.compactMap {
            SFSpeechRecognizer(locale: Locale(identifier: $0))
        }.first {
            $0.supportsOnDeviceRecognition && $0.isAvailable
        }
    }

    private func normalizeCommand(_ words: String) -> String {
        let folded = words.lowercased()
            .folding(options: [.diacriticInsensitive], locale: language.locale)
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespaces.contains(scalar)
                ? Character(String(scalar))
                : " "
        }
        var tokens = String(cleaned).split(whereSeparator: \.isWhitespace).map(String.init)
        let fillers: Set<String> = ["please", "tolong", "hey", "itera"]
        while let first = tokens.first, fillers.contains(first) {
            tokens.removeFirst()
        }
        return tokens.joined(separator: " ")
    }

    private func scheduleListeningRestart(after delay: Double) {
        tearDownListening(notify: false)
        recognitionRestartTask?.cancel()
        recognitionRestartTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            self.recognitionRestartTask = nil
            _ = self.startListening()
        }
    }

    /// Logs configuration only; never logs recognized words or microphone samples.
    private func logAudioConfiguration(_ context: String) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        logger.notice("Audio \(context, privacy: .public): category=\(session.category.rawValue, privacy: .public) mode=\(session.mode.rawValue, privacy: .public) outputs=\(outputs, privacy: .public) systemVolume=\(session.outputVolume)")
    }

    func stopListening() {
        recognitionRestartTask?.cancel()
        recognitionRestartTask = nil
        tearDownListening(notify: true)
    }

    private func tearDownListening(notify: Bool) {
        recognitionGeneration = UUID()
        recognizer?.delegate = nil
        recognizer = nil
        recognition?.cancel()
        recognition = nil
        request?.endAudio()
        request = nil
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if notify {
            events.send(.listening(false))
        }
    }

    func startMusic() {
        do {
            try NarrationAudioSession.activate(listening: tapInstalled)
            music.start()
        } catch {
            // Music is optional; retain the existing narration/listening recovery flow.
            music.stop()
        }
    }

    func pauseMusic() { music.pause() }

    func resumeMusic() { startMusic() }

    func stopMusic() { music.stop() }

    func stop() {
        music.stop()
        cancelSpeech()
        stopListening()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private enum AudioFailure: Error { case inputUnavailable }
}
