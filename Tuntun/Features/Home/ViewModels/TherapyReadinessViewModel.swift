//
//  TherapyReadinessViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class TherapyReadinessViewModel {
    private(set) var busy = false
    private(set) var message = "home.setup"
    private(set) var action = "home.enablePermissions"
    private(set) var ready = false
    /// Raised while an explicit Start validates listening, so the intro shows the loading
    /// overlay. A successful start leaves it raised: the session opens in the same turn and
    /// shows its own overlay, so the two join without a gap.
    private(set) var preparingSession = false

    @ObservationIgnored private let permissionService: any PermissionServiceProtocol
    @ObservationIgnored private let audioService: any SessionAudioServiceProtocol
    @ObservationIgnored private let historyRecoveryService: any HistoryRecoveryServiceProtocol

    init(
        permissionService: any PermissionServiceProtocol,
        audioService: any SessionAudioServiceProtocol,
        historyRecoveryService: any HistoryRecoveryServiceProtocol
    ) {
        self.permissionService = permissionService
        self.audioService = audioService
        self.historyRecoveryService = historyRecoveryService
    }

    func refresh() {
        guard !busy else { return }
        preparingSession = false
        evaluate()
    }

    private func evaluate() {
        permissionService.refresh()
        audioService.prepare()
        ready = false
        if historyRecoveryService.recoveryFailure != nil {
            message = "session.recoveryError"
            action = "home.retry"
            return
        }
        let requirement = PermissionRequirement.evaluate(
            AppPermission.allCases,
            in: permissionService
        )
        switch requirement {
        case .granted:
            break
        case .needsPrompt:
            message = "home.setup"
            action = "home.enablePermissions"
            return
        case .denied:
            // Names every refused permission, so one trip to Settings can fix them all.
            message = requirement.messageKey ?? "home.permissionUnavailable"
            action = "home.openSettings"
            return
        case .restricted, .unavailable:
            message = requirement.messageKey ?? "home.permissionUnavailable"
            action = "home.recheck"
            return
        }
        switch audioService.capability() {
        case .ready:
            ready = true
            message = "home.ready"
            action = "therapy.session.start"
        case .unsupported:
            message = "home.voiceUnsupported"
            action = "home.recheck"
        case .unavailable:
            message = "home.voiceUnavailable"
            action = "home.retry"
        }
    }

    /// Returns navigation intent only after an explicit Start and successful input startup.
    func performAction() async -> Bool {
        guard !busy else { return false }
        busy = true
        preparingSession = true

        // Preparing audio blocks the main actor, so the overlay is drawn before it starts.
        try? await Task.sleep(for: TMLoadingOverlay.presentationDelay)
        evaluate()

        if action == "home.openSettings" {
            busy = false
            preparingSession = false
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return false
        }

        let starting = ready
        if historyRecoveryService.recoveryFailure != nil || historyRecoveryService.recovering {
            await historyRecoveryService.recoverHistory()
        } else if starting {
            let result = await audioService.startListening()
            audioService.stop()
            busy = false
            guard result == .started else {
                preparingSession = false
                ready = false
                message = "home.voiceStartupFailed"
                action = "home.retry"
                return false
            }
            return true
        } else {
            // Permission prompts are system UI; the overlay must not sit beneath them.
            preparingSession = false

            // Every unasked permission is prompted in this one pass, even after a refusal, so
            // the message that follows names all that are still missing.
            for permission in AppPermission.allCases {
                _ = await permissionService.request(permission)
            }
        }
        busy = false
        refresh()
        return false
    }
}
