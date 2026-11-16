//
//  DailyPlanIntroNarration.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 14/11/2026.
//

import Combine
import Foundation
import Observation

/// Reads the approved introduction one clip at a time before opening calibration.
/// Completion identities reject late callbacks after Back, interruption, or navigation.
@MainActor
@Observable
final class DailyPlanIntroNarration {
    private(set) var running = false
    private(set) var paused = false
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var audio: SessionAudioService?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var lineIndex = 0
    @ObservationIgnored private var lineKeys: [String] = []
    @ObservationIgnored private var completion: (() -> Void)?

    func start(
        readiness: HomeViewModel,
        plan: DailyPlanViewModel,
        audio: SessionAudioService,
        router: NavigationRouter,
        itemID: String,
        automatic: Bool,
        lines: [String]
    ) async {
        guard !running else {
            return
        }
        let operation = UUID()
        operationID = operation
        // The intro is playback, not therapy. Do not silence it when microphone or command
        // recognition readiness is pending; startCurrent validates that before opening capture.
        guard operationID == operation, plan.isRunning,
              plan.nextSessionItemID == itemID else {
            return
        }
        lineKeys = lines
        begin(audio: audio) {
            Task { @MainActor in
                guard self.operationID == operation,
                      plan.isRunning,
                      plan.nextSessionItemID == itemID else {
                    return
                }
                if automatic {
                    plan.launchAfterRest(router: router)
                } else {
                    await plan.startCurrent(
                        readiness: readiness,
                        router: router
                    )
                }
            }
        }
    }

    private func begin(audio: SessionAudioService, completion: @escaping () -> Void) {
        guard !running else {
            return
        }
        self.audio = audio
        self.completion = completion
        running = true
        paused = false
        lineIndex = 0
        audio.prepareRestNarration()
        subscription = audio.events.sink { [weak self] event in
            guard let self, self.running else {
                return
            }
            switch event {
            case .completed(let id, _) where id == self.requestID:
                self.requestID = nil
                self.lineIndex += 1
                self.speakNext()
            case .interrupted:
                self.pause()
            case .command(.pause):
                self.pause()
            case .command(.resume):
                self.resume()
            default:
                break
            }
        }
        speakNext()
    }

    func pause() {
        guard running else {
            return
        }
        paused = true
        requestID = nil
        audio?.cancelSpeech()
    }

    func resume() {
        guard running, paused else {
            return
        }
        paused = false
        speakNext()
    }

    func stop() {
        let wasRunning = running
        running = false
        operationID = nil
        requestID = nil
        subscription = nil
        completion = nil
        if wasRunning {
            audio?.cancelSpeech()
        }
    }

    private func speakNext() {
        guard running, !paused else {
            return
        }
        guard lineKeys.indices.contains(lineIndex) else {
            running = false
            requestID = nil
            subscription = nil
            let completion = completion
            self.completion = nil
            completion?()
            return
        }
        let key = lineKeys[lineIndex]
        let id = UUID()
        requestID = id
        audio?.speak(id: id, key: key)
    }
}
