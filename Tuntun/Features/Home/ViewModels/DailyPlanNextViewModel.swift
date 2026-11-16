//
//  DailyPlanNextViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Combine
import Foundation
import Observation

@MainActor
protocol DailyPlanNextViewModelProtocol: AnyObject, Observable {
    /// The next exercise after the rest; nil once today's plan is done.
    var nextSessionItemID: String? { get }
    var nextSessionTitleKey: String? { get }
    /// The next item reads its own scripted introduction instead of a countdown.
    var usesNextScript: Bool { get }
    var usesScriptedLongRest: Bool { get }
    /// Key prefix of the recorded long-rest lines for the scripted side, if any.
    var longRestNarrationPrefix: String? { get }
    var audioEvents: AnyPublisher<AudioEvent, Never> { get }

    func prepareRestNarration()
    func startMusic()
    func pauseMusic()
    func stopMusic()
    func cancelSpeech()
    func playCountdown(_ seconds: Int)
    func speak(id: UUID, key: String, argument: Int?)
    func launchAfterRest()
    func end()
}

/// The rest and countdown between daily-plan exercises, or the page after the last one. The
/// page owns its breathing stages; this model owns the plan and the shared audio it drives.
@MainActor
@Observable
final class DailyPlanNextViewModel: DailyPlanNextViewModelProtocol {
    private let plan: DailyPlanViewModel
    @ObservationIgnored private let audio: SessionAudioService

    init(plan: DailyPlanViewModel, audio: SessionAudioService) {
        self.plan = plan
        self.audio = audio
    }

    // MARK: - State

    var nextSessionItemID: String? {
        plan.nextSessionItemID
    }

    var nextSessionTitleKey: String? {
        plan.nextSessionTitleKey
    }

    var usesNextScript: Bool {
        guard let itemID = plan.nextSessionItemID else {
            return false
        }

        return plan.usesOppositionScript(itemID: itemID)
            || plan.usesArmRaiseScript(itemID: itemID)
    }

    var usesScriptedLongRest: Bool {
        plan.usesScriptedLongRest
    }

    var longRestNarrationPrefix: String? {
        plan.longRestNarrationPrefix
    }

    var audioEvents: AnyPublisher<AudioEvent, Never> {
        audio.events.eraseToAnyPublisher()
    }

    // MARK: - Audio

    func prepareRestNarration() {
        audio.prepareRestNarration()
    }

    func startMusic() {
        audio.startMusic()
    }

    func pauseMusic() {
        audio.pauseMusic()
    }

    func stopMusic() {
        audio.stopMusic()
    }

    func cancelSpeech() {
        audio.cancelSpeech()
    }

    func playCountdown(_ seconds: Int) {
        audio.play(id: UUID(), cue: .countdown(seconds))
    }

    func speak(id: UUID, key: String, argument: Int?) {
        audio.speak(id: id, key: key, argument: argument)
    }

    // MARK: - Plan

    func launchAfterRest() {
        plan.launchAfterRest()
    }

    func end() {
        plan.end()
    }
}
