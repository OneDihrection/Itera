//
//  GuidanceAudioService.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import AVFoundation
import Combine
import Speech

// Service vocabulary is independent of exercise progression.
enum GuidanceSound {
    case countdown
    case holdCompleted
    case setCompleted
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
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionID = UUID()
    private var vocabulary = VoiceCommandVocabulary()
    private var pendingCommand: VoiceCommand?
    private var pendingCommandTask: Task<Void, Never>?
    private var utterances: [ObjectIdentifier: UUID] = [:]
    private let music = ExerciseMusicPlayer()
    private var cuePlayer: AVAudioPlayer?
    private var buttonPlayer: AVAudioPlayer?
    private var audioSessionActive = false
    private var lastButtonSound = 0.0
    private var interruption: NSObjectProtocol?
    private var tapInstalled = false
    private(set) var voiceEnabled = false
    private var locale = "id-ID"
    /// Chosen once per configuration: the best installed voice for `locale`.
    private var voice: AVSpeechSynthesisVoice?
    /// Recorded narration for the current cue, played in order; see `NarrationClips`.
    private var narrationID: UUID?
    private var narrationQueue: [PreparedAudioClip] = []
    private var narrationClip: PreparedAudioClip?
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
    }

    deinit {
        if let interruption {
            NotificationCenter.default.removeObserver(interruption)
        }
    }

    func configure(language: String) throws {
        locale = language
        voice = NarrationVoice.best(for: language)
        vocabulary = VoiceCommandVocabulary()
        try applySessionMode(listening: voiceEnabled)
        audioSessionActive = true
    }

    /// Speaks one cue. When every line has a bundled recording, those play in order;
    /// otherwise, or if a recording fails, `text` is spoken by the system voice.
    /// Either way the cue reports `.completed` exactly once.
    @discardableResult
    func speak(_ text: String, lines: [NarrationLine] = []) -> UUID {
        cancelSpeech()
        let id = UUID()
        music.setDucked(true)

        if let recorded = recordedClips(for: lines) {
            narrationID = id
            narrationQueue = recorded
            playNextNarrationClip(id: id, fallback: text)
            return id
        }

        synthesize(text, id: id)
        return id
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
            let name = NarrationClips.resourceName(for: line)

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
            music.setDucked(false)
            events.send(.completed(id))
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

    private func stopNarrationClips() {
        narrationID = nil
        narrationQueue.removeAll()
        narrationClip?.stop()
        narrationClip = nil
    }

    func playButtonClick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastButtonSound > 0.04 else {
            return
        }
        lastButtonSound = now
        do {
            try prepareOptionalPlayback()
            if buttonPlayer == nil, let url = Bundle.main.url(forResource: "button-click", withExtension: "wav") {
                buttonPlayer = try AVAudioPlayer(contentsOf: url)
                buttonPlayer?.volume = 0.18
                buttonPlayer?.prepareToPlay()
            }
            buttonPlayer?.currentTime = 0
            buttonPlayer?.play()
        } catch {
            // Optional touch reinforcement must not disable an action or interrupt narration.
            buttonPlayer = nil
        }
    }

    private func prepareOptionalPlayback() throws {
        guard !audioSessionActive else {
            return
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        audioSessionActive = true
    }

    func playAchievementCue() {
        do {
            try prepareOptionalPlayback()
            playCue(.setCompleted)
        } catch {
            // Celebrations remain usable when optional sound is unavailable.
        }
    }

    func playCue(_ cue: GuidanceSound) {
        let name: String
        switch cue {
        case .countdown: name = "countdown"
        case .holdCompleted: name = "target-reached"
        case .setCompleted: name = "set-complete"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            return
        }
        do {
            cuePlayer?.stop()
            cuePlayer = try AVAudioPlayer(contentsOf: url)
            cuePlayer?.volume = 0.30
            cuePlayer?.prepareToPlay()
            cuePlayer?.play()
        } catch {
            // Optional reinforcement never blocks readable guidance or progression.
            cuePlayer = nil
        }
    }

    /// True when recorded countdown numbers are bundled for the session language.
    var hasRecordedCounts: Bool {
        NarrationClips.countURL(1, language: narrationLanguage) != nil
    }

    /// Speaks a countdown number ("tiga") in the recorded voice, on the cue channel so it
    /// never cancels narration. Returns false when no recording exists, so the caller can
    /// fall back to the beep.
    func playCount(_ number: Int) -> Bool {
        guard let url = NarrationClips.countURL(number, language: narrationLanguage) else {
            return false
        }

        do {
            cuePlayer?.stop()
            let player = try AVAudioPlayer(contentsOf: url)
            // Spoken numbers are guidance, so they play at full narration level, not cue level.
            player.volume = 1
            player.prepareToPlay()
            cuePlayer = player
            return player.play()
        } catch {
            cuePlayer = nil
            return false
        }
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

    func cancelSpeech() {
        stopNarrationClips()
        utterances.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        music.setDucked(false)
    }

    func enableVoice() throws -> Bool {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted,
              let candidate = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              candidate.isAvailable, candidate.supportsOnDeviceRecognition else { return false }
        recognizer = candidate
        voiceEnabled = true
        do {
            try applySessionMode(listening: true)
            try beginRecognition()
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
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        // Spoken-audio playback once nothing is listening.
        if audioSessionActive {
            try? applySessionMode(listening: false)
        }
    }

    private func applySessionMode(listening: Bool) throws {
        try NarrationAudioSession.activate(listening: listening, allowsBluetoothMicrophone: true)
    }

    private func beginRecognition() throws {
        cancelPendingCommand()
        recognitionID = UUID()
        let id = recognitionID
        recognition?.cancel()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioError.unavailable
        }
        let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        bufferRequest.requiresOnDeviceRecognition = true
        bufferRequest.shouldReportPartialResults = true
        bufferRequest.contextualStrings = vocabulary.contextualStrings
        request = bufferRequest
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            bufferRequest.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        if !engine.isRunning {
            try engine.start()
        }
        recognition = recognizer?.recognitionTask(with: bufferRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.voiceEnabled, self.recognitionID == id else {
                    return
                }
                // An exact partial command can interrupt speech without waiting for finalization.
                // Rotating the request identity discards its later partial/final revisions.
                let command = result.flatMap { self.vocabulary.command(in: $0.bestTranscription.formattedString) }
                if let command {
                    if result?.isFinal == true || command == .pause || command == .stop {
                        self.consumeCommand(command, requestID: id)
                    } else {
                        self.scheduleCommand(command, requestID: id)
                    }
                } else {
                    self.cancelPendingCommand()
                    if result?.isFinal == true {
                        do {
                            try self.beginRecognition()
                        } catch {
                            self.voiceFailed()
                        }
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
            // Resume/repeat must remain an exact phrase briefly; expanded conversation cancels it.
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
        do {
            try beginRecognition()
        } catch {
            voiceFailed()
        }
    }

    private func cancelPendingCommand() {
        pendingCommandTask?.cancel()
        pendingCommandTask = nil
        pendingCommand = nil
    }

    private func voiceFailed() {
        disableVoice()
        events.send(.voiceUnavailable)
    }

    func suspend() {
        cancelSpeech()
        music.pause()
        cuePlayer?.stop()
        disableVoice()
    }

    func pauseAmbient() {
        music.pause()
        cuePlayer?.stop()
    }

    func startMusic() {
        do {
            try applySessionMode(listening: voiceEnabled)
            audioSessionActive = true
            music.start()
        } catch {
            music.pause()
        }
    }

    func resumeAmbient() { startMusic() }

    func stop() {
        suspend()
        music.stop()
        buttonPlayer?.stop()
        audioSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        NarrationAudioSession.noteDeactivated()
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

