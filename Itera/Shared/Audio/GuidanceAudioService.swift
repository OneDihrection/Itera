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
enum GuidanceSound { case countdown, setCompleted }

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
    private var ambient: AVAudioPlayer?
    private var cuePlayer: AVAudioPlayer?
    private var buttonPlayer: AVAudioPlayer?
    private var audioSessionActive = false
    private var lastButtonSound = 0.0
    private var interruption: NSObjectProtocol?
    private var tapInstalled = false
    private(set) var voiceEnabled = false
    private var locale = "id-ID"

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

    func configure(language: String, ambientSound: Bool) throws {
        locale = language
        vocabulary = VoiceCommandVocabulary()
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setActive(true)
        audioSessionActive = true
        if ambientSound, let url = Bundle.main.url(forResource: "calm", withExtension: "wav") {
            ambient = try AVAudioPlayer(contentsOf: url)
            ambient?.numberOfLoops = -1
            ambient?.volume = 0.08
            ambient?.play()
        }
    }

    @discardableResult
    func speak(_ text: String) -> UUID {
        cancelSpeech()
        let id = UUID()
        guard let voice = AVSpeechSynthesisVoice(language: locale) else {
            Task { events.send(.narrationUnavailable(id)) }
            return id
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 0.40
        utterances[ObjectIdentifier(utterance)] = id
        ambient?.volume = 0.015
        synthesizer.speak(utterance)
        return id
    }

    func playButtonClick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastButtonSound > 0.04 else {
            return
        }
        lastButtonSound = now
        do {
            // The same owner configures quiet UI playback outside therapy sessions.
            if !audioSessionActive {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                audioSessionActive = true
            }
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

    func playCue(_ cue: GuidanceSound) {
        let name = cue == .setCompleted ? "set-complete" : "countdown"
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

    func cancelSpeech() {
        utterances.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        ambient?.volume = 0.08
    }

    func enableVoice() throws -> Bool {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted,
              let candidate = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              candidate.isAvailable, candidate.supportsOnDeviceRecognition else { return false }
        recognizer = candidate
        voiceEnabled = true
        do {
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
        ambient?.pause()
        cuePlayer?.stop()
        disableVoice()
    }

    func pauseAmbient() {
        ambient?.pause()
        cuePlayer?.stop()
    }

    func resumeAmbient() { ambient?.play() }

    func stop() {
        suspend()
        ambient = nil
        buttonPlayer?.stop()
        audioSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let id = utterances.removeValue(forKey: ObjectIdentifier(utterance)) else {
                return
            }
            ambient?.volume = 0.08
            events.send(.completed(id))
        }
    }

    private enum AudioError: Error { case unavailable }
}
