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
        permissionService.refresh()
        audioService.prepare()
        ready = false
        if historyRecoveryService.recoveryFailure != nil {
            message = "session.recoveryError"
            action = "home.retry"
            return
        }
        if let missing = AppPermission.allCases.first(where: {
            permissionService.status(for: $0) != .authorized
        }) {
            switch permissionService.status(for: missing) {
            case .denied:
                message = permissionMessage(missing)
                action = "home.openSettings"
            case .restricted:
                message = "home.restricted"
                action = "home.recheck"
            case .notDetermined:
                message = "home.setup"
                action = "home.enablePermissions"
            default:
                message = "home.permissionUnavailable"
                action = "home.recheck"
            }
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
        refresh()
        if action == "home.openSettings" {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return false
        }
        let starting = ready
        busy = true
        if historyRecoveryService.recoveryFailure != nil || historyRecoveryService.recovering {
            await historyRecoveryService.recoverHistory()
        } else if starting {
            let result = await audioService.startListening()
            audioService.stop()
            busy = false
            guard result == .started else {
                ready = false
                message = "home.voiceStartupFailed"
                action = "home.retry"
                return false
            }
            return true
        } else {
            for permission in AppPermission.allCases {
                guard await permissionService.request(permission) == .authorized else { break }
            }
        }
        busy = false
        refresh()
        return false
    }

    private func permissionMessage(_ permission: AppPermission) -> String {
        switch permission {
        case .camera: return "home.cameraDenied"
        case .microphone: return "home.microphoneDenied"
        case .speechRecognition: return "home.speechDenied"
        }
    }
}
