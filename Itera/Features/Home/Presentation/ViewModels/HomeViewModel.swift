//
//  HomeViewModel.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation
import Observation
import UIKit

@MainActor
protocol HistoryRecovering: AnyObject {
    var recovering: Bool { get }
    var recoveryFailure: String? { get }
    func recoverHistory() async
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var busy = false
    private(set) var message = "home.setup"
    private(set) var action = "home.enablePermissions"
    private(set) var ready = false

    @ObservationIgnored private let permissions: any PermissionManaging
    @ObservationIgnored private let audio: any VoiceReadinessProviding
    @ObservationIgnored private let history: any HistoryRecovering

    init(
        permissions: any PermissionManaging,
        audio: any VoiceReadinessProviding,
        history: any HistoryRecovering
    ) {
        self.permissions = permissions
        self.audio = audio
        self.history = history
    }

    func refresh() {
        guard !busy else { return }
        permissions.refresh()
        audio.prepare()
        ready = false
        if history.recoveryFailure != nil {
            message = "session.recoveryError"
            action = "home.retry"
            return
        }
        if let missing = AppPermission.allCases.first(where: {
            permissions.status(for: $0) != .authorized
        }) {
            switch permissions.status(for: missing) {
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
        switch audio.capability() {
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
        if history.recoveryFailure != nil || history.recovering {
            await history.recoverHistory()
        } else if starting {
            let result = audio.startListening()
            audio.stop()
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
                guard await permissions.request(permission) == .authorized else { break }
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
