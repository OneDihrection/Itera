// AudioInputWorker.swift
// Created by dimaswisodewo on 02/11/2026.

import AVFoundation
import Speech

/// Serial ownership of blocking audio hardware operations; the tap only reads a locked request.
final class AudioInputWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Itera.audioInput", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var installed = false
    private var voiceProcessingConfigured = false

    func replaceRequest(_ value: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = value
        lock.unlock()
    }

    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                do {
                    // The same configuration the narrators use, so nothing flips mid-playback.
                    try NarrationAudioSession.activate()
                    let input = self.engine.inputNode
                    self.enableVoiceProcessingIfNeeded(on: input)
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else {
                        throw CocoaError(.validationMissingMandatoryProperty)
                    }
                    if !self.installed {
                        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                            guard let self else { return }
                            self.lock.lock()
                            self.request?.append(buffer)
                            self.lock.unlock()
                        }
                        self.installed = true
                    }
                    self.engine.prepare()
                    try self.engine.start()
                    continuation.resume(returning: true)
                } catch {
                    self.stopEngine()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func stop(deactivate: Bool = false) {
        replaceRequest(nil)
        // Taken now, not on the queue: an activation in between means the session is wanted again.
        let token = NarrationAudioSession.activationToken
        queue.async {
            self.stopEngine()
            if deactivate {
                NarrationAudioSession.deactivate(ifUnchangedSince: token)
            }
        }
    }

    /// Echo cancellation and noise suppression, off by default. Voice processing routes all
    /// output through the call-style voice path, which made narration and music noticeably
    /// quieter once listening started (and only in sessions using this worker), even with
    /// minimum ducking. Debug builds can enable it to compare recognition on a device.
    ///
    /// Configured once, before the engine first starts; a failure leaves listening without it.
    private func enableVoiceProcessingIfNeeded(on input: AVAudioInputNode) {
        guard !voiceProcessingConfigured, Self.voiceProcessingRequested else {
            return
        }

        do {
            try input.setVoiceProcessingEnabled(true)
            input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                enableAdvancedDucking: false,
                duckingLevel: .min
            )
            voiceProcessingConfigured = true
            #if DEBUG
            NSLog("Voice processing enabled for listening")
            #endif
        } catch {
            NSLog("Voice processing unavailable: %@", error.localizedDescription)
        }
    }

    /// Debug launch argument to compare listening and loudness with voice processing.
    private static var voiceProcessingRequested: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-IteraVoiceProcessing")
        #else
        return false
        #endif
    }

    private func stopEngine() {
        engine.stop()
        if installed {
            engine.inputNode.removeTap(onBus: 0)
            installed = false
        }
    }
}
