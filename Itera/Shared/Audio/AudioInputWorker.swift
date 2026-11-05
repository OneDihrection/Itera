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

    func replaceRequest(_ value: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = value
        lock.unlock()
    }

    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                do {
                    let session = AVAudioSession.sharedInstance()
                    var mode: AVAudioSession.Mode = .default
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains(NarrationAudioSession.voiceChatComparisonArgument) {
                        mode = .voiceChat
                    }
                    #endif
                    try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker])
                    try session.setActive(true)
                    let input = self.engine.inputNode
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
        queue.async {
            self.stopEngine()
            if deactivate {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private func stopEngine() {
        engine.stop()
        if installed {
            engine.inputNode.removeTap(onBus: 0)
            installed = false
        }
    }
}
