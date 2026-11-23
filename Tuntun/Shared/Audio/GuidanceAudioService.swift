//
//  GuidanceAudioService.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import AVFoundation
import Combine
import Speech

// Service vocabulary is independent of exercise progression.
enum GuidanceSound {
    case countdown
    /// A soft bubble pop when a finger hold's circle completes.
    case holdPopped
    case setCompleted
    /// The live demonstration moved to a new step.
    case demoChanged
}

enum GuidanceAudioEvent {
    case completed(UUID)
    case narrationUnavailable(UUID)
    case command(VoiceCommand)
    case voiceUnavailable
    case interrupted
}

@MainActor
final class GuidanceAudioService: NSObject, AVSpeechSynthesizerDelegate {
    let events = PassthroughSubject<GuidanceAudioEvent, Never>()
    private let synthesizer = AVSpeechSynthesizer()
    /// Owns the microphone engine on its own queue: stopping an engine with a running input node
    /// waits for audio I/O, which froze the screen when a finger session finished.
    private let inputWorker = AudioInputWorker()
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionID = UUID()
    private var vocabulary = VoiceCommandVocabulary()
    private var pendingCommand: VoiceCommand?
    private var pendingCommandTask: Task<Void, Never>?
    private var utterances: [ObjectIdentifier: UUID] = [:]
    private let music = ExerciseMusicPlayer()
    /// Music waiting for the audio session; pausing or stopping cancels it so it cannot start late.
    private var musicStart: Task<Void, Never>?
    /// The cue or number playing now; cues and numbers share one channel.
    private var cueClip: PreparedAudioClip?
    /// Loaded once per file: building an `AVAudioPlayer` on the main thread for every cue stalled
    /// set ends, countdowns and hold seconds. `PreparedAudioClip` loads and plays off the main thread.
    private var cueClips: [URL: PreparedAudioClip] = [:]
    /// Plays off the main thread like the cues: preparing or playing an `AVAudioPlayer` on the
    /// main thread calls into the audio session and warned about UI unresponsiveness.
    private var buttonClip: PreparedAudioClip?
    private var lastButtonSound = 0.0
    private var interruption: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private(set) var voiceEnabled = false
    private var locale = "id-ID"
    /// Chosen once per configuration: the best installed voice for `locale`.
    private var voice: AVSpeechSynthesisVoice?
    /// Recorded narration for the current cue, played in order; see `NarrationClips`.
    private var narrationID: UUID?
    private var narrationQueue: [PreparedAudioClip] = []
    private var narrationClip: PreparedAudioClip?
    /// Starts the next cue once the line it replaces has finished or faded (`speak`).
    private var afterNarration: (() -> Void)?
    /// The quiet moment after a faded line, before the next cue starts.
    private var handOffGap: Task<Void, Never>?

    /// A line with at most this much left finishes before the next cue; a longer one fades out.
    private static let handOffFinishWindow: TimeInterval = 1.0
    private static let handOffFade: TimeInterval = 0.25
    private static let handOffPause: TimeInterval = 0.3
    private var loadedClips: [String: PreparedAudioClip] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in
                self?.stop()
                self?.events.send(.interrupted)
            }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { _ in
            NarrationAudioSession.handleRouteChange()
        }
    }

    deinit {
        if let interruption {
            NotificationCenter.default.removeObserver(interruption)
        }

        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }

    func configure(language: String) async throws {
        locale = language
        voice = NarrationVoice.best(for: language)
        vocabulary = VoiceCommandVocabulary()
        preloadCues()
        try await activateSession()
    }

    /// Loads the cues and numbers a set's end, a countdown and hold seconds play, under the
    /// session's loading overlay instead of at those moments.
    private func preloadCues() {
        let effects = ["countdown", HoldPopSound.resourceName, "set-complete", DemoChangeSound.resourceName]
            .compactMap { Bundle.main.url(forResource: $0, withExtension: "wav") }
        let countdowns = (1...10).compactMap { NarrationClips.countdownURL($0, language: narrationLanguage) }
        let counts = (1...10).compactMap { NarrationClips.countURL($0, language: narrationLanguage) }

        for url in effects + countdowns + counts {
            _ = cueClip(for: url)
        }
    }

    /// Speaks one cue. When every line has a bundled recording, those play in order;
    /// otherwise, or if a recording fails, `text` is spoken by the system voice.
    /// Either way the cue reports `.completed` exactly once.
    ///
    /// A cue still playing is handed off, never cut: its current line finishes and its remaining
    /// lines are dropped, or, with more than a second left, the line fades out and the new cue
    /// starts after a short pause. The replaced cue's late `.completed` carries its own identity.
    /// Call `cancelSpeech` first where speech must stop at once.
    @discardableResult
    func speak(_ text: String, lines: [NarrationLine] = []) -> UUID {
        let id = UUID()
        music.setDucked(true)
        handOff { [weak self] in
            self?.start(id, text: text, lines: lines)
        }
        return id
    }

    private func handOff(then start: @escaping () -> Void) {
        handOffGap?.cancel()
        handOffGap = nil
        afterNarration = nil

        if narrationID != nil, let clip = narrationClip {
            narrationQueue.removeAll()

            if let remaining = clip.remaining(), remaining <= Self.handOffFinishWindow {
                afterNarration = start
                return
            }

            stopNarrationClips(fade: Self.handOffFade)
            startAfterGap(start)
            return
        }

        guard !utterances.isEmpty else {
            stopNarrationClips()
            start()
            return
        }

        utterances.removeAll()
        synthesizer.stopSpeaking(at: .word)
        startAfterGap(start)
    }

    private func startAfterGap(_ start: @escaping () -> Void) {
        handOffGap = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.handOffFade + Self.handOffPause))
            } catch {
                return
            }

            self?.handOffGap = nil
            start()
        }
    }

    private func start(_ id: UUID, text: String, lines: [NarrationLine]) {
        music.setDucked(true)

        if let recorded = recordedClips(for: lines) {
            narrationID = id
            narrationQueue = recorded
            playNextNarrationClip(id: id, fallback: text)
            return
        }

        synthesize(text, id: id)
    }

    private func synthesize(_ text: String, id: UUID) {
        guard let voice = voice ?? NarrationVoice.best(for: locale) else {
            music.setDucked(false)
            Task { events.send(.narrationUnavailable(id)) }
            return
        }
        let utterance = NarrationVoice.utterance(text, voice: voice)
        utterances[ObjectIdentifier(utterance)] = id
        synthesizer.speak(utterance)
    }

    // MARK: - Recorded narration

    /// Loaded recordings for all lines, or `nil` when any is missing (never a partial cue).
    private func recordedClips(for lines: [NarrationLine]) -> [PreparedAudioClip]? {
        guard !lines.isEmpty else {
            return nil
        }

        let language: AppLanguage = locale.hasPrefix("id") ? .indonesian : .english
        var clips: [PreparedAudioClip] = []

        for line in lines {
            let name = NarrationClips.resourceName(for: line, language: language)

            if let cached = loadedClips[name] {
                clips.append(cached)
                continue
            }

            guard let url = NarrationClips.url(for: line, language: language),
                  let clip = try? PreparedAudioClip(url: url) else {
                return nil
            }

            loadedClips[name] = clip
            clips.append(clip)
        }

        return clips
    }

    private func playNextNarrationClip(id: UUID, fallback text: String) {
        guard narrationID == id else {
            return
        }

        guard !narrationQueue.isEmpty else {
            stopNarrationClips()
            events.send(.completed(id))
            finishHandOff()
            return
        }

        let clip = narrationQueue.removeFirst()
        narrationClip = clip

        let started = clip.play(id: id) { [weak self] id, success in
            guard let self, self.narrationID == id else {
                return
            }

            if success {
                self.playNextNarrationClip(id: id, fallback: text)
            } else if self.afterNarration != nil {
                // The cue was already being replaced; go straight to its successor.
                self.stopNarrationClips()
                self.finishHandOff()
            } else {
                self.stopNarrationClips()
                self.synthesize(text, id: id)
            }
        }

        if !started {
            stopNarrationClips()
            synthesize(text, id: id)
        }
    }

    private func stopNarrationClips(fade: TimeInterval = 0.04) {
        narrationID = nil
        narrationQueue.removeAll()
        narrationClip?.stop(fade: fade)
        narrationClip = nil
    }

    /// Starts the cue waiting on the line that just ended, or lets the music back up.
    private func finishHandOff() {
        guard let start = afterNarration else {
            music.setDucked(false)
            return
        }

        afterNarration = nil
        start()
    }

    func playButtonClick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastButtonSound > 0.04 else {
            return
        }
        lastButtonSound = now

        guard NarrationAudioSession.isSessionActive else {
            // Only the first tap after a deactivation waits for the session to come back.
            Task { [weak self] in
                do {
                    try await self?.activateSession()
                    self?.playButtonSound()
                } catch {
                    // Optional touch reinforcement must not disable an action or interrupt narration.
                }
            }
            return
        }

        playButtonSound()
    }

    private func playButtonSound() {
        if buttonClip == nil, let url = Bundle.main.url(forResource: "button-click", withExtension: "wav") {
            buttonClip = try? PreparedAudioClip(url: url)
        }

        // Optional touch reinforcement must not disable an action or interrupt narration.
        _ = buttonClip?.play(id: UUID(), volume: 0.18) { _, _ in }
    }

    func playCue(_ cue: GuidanceSound) {
        let name: String
        switch cue {
        case .countdown: name = "countdown"
        case .holdPopped: name = HoldPopSound.resourceName
        case .setCompleted: name = "set-complete"
        case .demoChanged: name = DemoChangeSound.resourceName
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            return
        }
        // Optional reinforcement never blocks readable guidance or progression.
        _ = playOnCueChannel(url, volume: 0.30)
    }

    /// True when recorded countdown numbers are bundled for the session language.
    var hasRecordedCounts: Bool {
        NarrationClips.countURL(1, language: narrationLanguage) != nil
    }

    /// Speaks a countdown number ("tiga") in the recorded voice, on the cue channel so it
    /// never cancels narration. Returns false when no recording exists, so the caller can
    /// fall back to the beep.
    func playCount(_ number: Int) -> Bool {
        playNumber(NarrationClips.countURL(number, language: narrationLanguage))
    }

    func playCountdown(_ number: Int) -> Bool {
        playNumber(NarrationClips.countdownURL(number, language: narrationLanguage))
    }

    private func playNumber(_ url: URL?) -> Bool {
        guard let url else {
            return false
        }

        // Spoken numbers are guidance, so they play at full narration level, not cue level.
        return playOnCueChannel(url, volume: 1)
    }

    private func playOnCueChannel(_ url: URL, volume: Float) -> Bool {
        cueClip?.stop()

        guard let clip = cueClip(for: url) else {
            cueClip = nil
            return false
        }

        cueClip = clip
        return clip.play(id: UUID(), volume: volume) { _, _ in }
    }

    private func cueClip(for url: URL) -> PreparedAudioClip? {
        if let clip = cueClips[url] {
            return clip
        }

        let clip = try? PreparedAudioClip(url: url)
        cueClips[url] = clip
        return clip
    }

    /// Speaks the number in the hold readout, only while no instruction is being spoken,
    /// so a number never talks over or cuts off guidance.
    ///
    /// - Returns: false only while an instruction is playing, so the caller can try again
    ///   once it ends with whatever number is shown then. True when the number was spoken,
    ///   or when there is nothing to retry (no number, or no recording).
    @discardableResult
    func playHoldSecond(_ number: Int) -> Bool {
        guard number > 0 else {
            return true
        }

        guard narrationID == nil, !synthesizer.isSpeaking else {
            return false
        }

        _ = playCount(number)
        return true
    }

    private var narrationLanguage: AppLanguage {
        locale.hasPrefix("id") ? .indonesian : .english
    }

    /// Discards an evidence-timed count when a hold is paused or its stage changes.
    func stopCount() {
        cueClip?.stop()
    }

    func cancelSpeech() {
        handOffGap?.cancel()
        handOffGap = nil
        afterNarration = nil
        stopNarrationClips()
        utterances.removeAll()
        // A synchronous call into the speech service; every countdown number cancels first, so
        // it is skipped when nothing is queued.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        music.setDucked(false)
    }

    func enableVoice() async throws -> Bool {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted,
              let candidate = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              candidate.isAvailable, candidate.supportsOnDeviceRecognition else { return false }
        recognizer = candidate
        voiceEnabled = true
        do {
            try await activateSession()

            guard await inputWorker.start() else {
                throw AudioError.unavailable
            }

            // Listening may have been switched off while the engine started.
            guard voiceEnabled else {
                inputWorker.stop()
                return false
            }

            beginRecognition()
            return true
        } catch {
            disableVoice()
            throw error
        }
    }

    func disableVoice() {
        cancelPendingCommand()
        voiceEnabled = false
        recognitionID = UUID()
        recognition?.cancel()
        recognition = nil
        request?.endAudio()
        request = nil
        inputWorker.stop()
        // The session keeps its configuration: switching category here changed loudness.
    }

    /// The shared configuration, so narration stays on the same loud route whether or not
    /// voice commands are listening.
    private func activateSession() async throws {
        try await NarrationAudioSession.activate(allowsBluetoothMicrophone: true)
    }

    /// Starts a new recognition request on the running input engine. The engine keeps running
    /// between requests; only the request its tap feeds is replaced.
    private func beginRecognition() {
        cancelPendingCommand()
        recognitionID = UUID()
        let id = recognitionID
        recognition?.cancel()
        let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        bufferRequest.requiresOnDeviceRecognition = true
        bufferRequest.shouldReportPartialResults = true
        bufferRequest.contextualStrings = vocabulary.contextualStrings
        request = bufferRequest
        inputWorker.replaceRequest(bufferRequest)
        recognition = recognizer?.recognitionTask(with: bufferRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.voiceEnabled, self.recognitionID == id else {
                    return
                }
                // An exact partial command can interrupt speech without waiting for finalization.
                // Rotating the request identity discards its later partial/final revisions.
                let command = result.flatMap { self.vocabulary.command(in: $0.bestTranscription.formattedString) }

                #if DEBUG
                // Temporary: diagnosing stop/go recognition on device.
                if let result {
                    LogManager.shared.notice("Voice transcript=\(result.bestTranscription.formattedString) final=\(result.isFinal) match=\(String(describing: command))", category: .voice)
                }
                if let error {
                    let nsError = error as NSError
                    LogManager.shared.error("Voice recognition failed", error: nsError, category: .voice)
                }
                #endif

                if let command {
                    if result?.isFinal == true || command == .pause {
                        self.consumeCommand(command, requestID: id)
                    } else {
                        self.scheduleCommand(command, requestID: id)
                    }
                } else {
                    self.cancelPendingCommand()
                    if result?.isFinal == true {
                        self.beginRecognition()
                    } else if error != nil {
                        self.voiceFailed()
                    }
                }
            }
        }
    }

    private func scheduleCommand(_ command: VoiceCommand, requestID: UUID) {
        guard pendingCommand != command else {
            return
        }
        cancelPendingCommand()
        pendingCommand = command
        pendingCommandTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.pendingCommand == command else {
                return
            }
            // Resume must remain an exact phrase briefly; expanded conversation cancels it.
            self.consumeCommand(command, requestID: requestID)
        }
    }

    private func consumeCommand(_ command: VoiceCommand, requestID: UUID) {
        guard voiceEnabled, recognitionID == requestID else {
            return
        }
        cancelPendingCommand()
        events.send(.command(command))
        // Stop may synchronously release the session. Never restart its microphone afterwards.
        guard voiceEnabled, recognitionID == requestID else {
            return
        }
        beginRecognition()
    }

    private func cancelPendingCommand() {
        pendingCommandTask?.cancel()
        pendingCommandTask = nil
        pendingCommand = nil
    }

    private func voiceFailed() {
        #if DEBUG
        // Temporary: diagnosing stop/go recognition on device.
        LogManager.shared.notice("Voice failed; listening stops", category: .voice)
        #endif

        disableVoice()
        events.send(.voiceUnavailable)
    }

    func suspend() {
        cancelSpeech()
        musicStart?.cancel()
        music.pause()
        cueClip?.stop()
        disableVoice()
    }

    func pauseAmbient() {
        musicStart?.cancel()
        music.pause()
        cueClip?.stop()
    }

    func startMusic() {
        musicStart?.cancel()
        musicStart = Task { [weak self] in
            do {
                try await self?.activateSession()
            } catch {
                self?.music.pause()
                return
            }

            guard !Task.isCancelled else {
                return
            }

            self?.music.start()
        }
    }

    func resumeAmbient() { startMusic() }

    func stop() {
        suspend()
        music.stop()
        buttonClip?.stop()
        NarrationAudioSession.deactivateInBackground()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let id = utterances.removeValue(forKey: ObjectIdentifier(utterance)) else {
                return
            }
            music.setDucked(false)
            events.send(.completed(id))
        }
    }

    private enum AudioError: Error { case unavailable }
}

