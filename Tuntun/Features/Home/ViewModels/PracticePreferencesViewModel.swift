//
//  PracticePreferencesViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation
import UIKit

/// What Settings offers when voice control lacks access: ask for it, send the caregiver to the
/// system Settings, or only explain that a device manager restricts it.
enum VoicePermissionFallback: Equatable {
    case request
    case openSettings(messageKey: String)
    case restricted

    var messageKey: String {
        switch self {
        case .request:
            return "settings.voiceNeedsAccess"
        case .openSettings(let messageKey):
            return messageKey
        case .restricted:
            return "home.restricted"
        }
    }

    /// The fallback button's title, or nil when nothing in the app can grant access.
    var actionKey: String? {
        switch self {
        case .request:
            return "home.enablePermissions"
        case .openSettings:
            return "home.openSettings"
        case .restricted:
            return nil
        }
    }
}


@MainActor
protocol PracticePreferencesViewModelProtocol: AnyObject, Observable {
    /// The daily plan's training side: empty for the default, otherwise a `HandSide` raw value.
    var sidePreference: String { get set }
    var sets: Int { get set }
    var repetitions: Int { get set }
    var restSeconds: Int { get set }
    var errorKey: String? { get }
    /// Voice control is always on; this mirrors whether microphone and speech access allow it.
    var voiceEnabled: Bool { get }
    var voiceFallback: VoicePermissionFallback? { get }

    /// Saves the finger routine and closes the sheet when saving succeeded.
    func done() async
    func save() async
    func refreshPermissions()
    /// Requests the missing voice permissions, or opens the system Settings when they were denied.
    func resolveVoiceAccess() async
}

/// The settings sheet: edits the same saved finger routine and plan side that Beranda uses.
/// A session in progress keeps the snapshot it started with.
@MainActor
@Observable
final class PracticePreferencesViewModel: PracticePreferencesViewModelProtocol {
    private let home: FingerHomeViewModel
    private let plan: DailyPlanViewModel
    @ObservationIgnored private let router: any HomeRouterProtocol
    /// Not ignored: its statuses are observable, so the voice row follows permission changes.
    private let permissionService: any PermissionServiceProtocol

    /// The permissions voice commands need; the camera is checked when a session starts.
    private static let voicePermissions: [AppPermission] = [.microphone, .speechRecognition]

    init(
        home: FingerHomeViewModel,
        plan: DailyPlanViewModel,
        router: any HomeRouterProtocol,
        permissionService: any PermissionServiceProtocol
    ) {
        self.home = home
        self.plan = plan
        self.router = router
        self.permissionService = permissionService
    }

    var sidePreference: String {
        get { plan.sidePreference }
        set { plan.sidePreference = newValue }
    }

    var sets: Int {
        get { home.routine.sets }
        set { home.routine.sets = newValue }
    }

    var repetitions: Int {
        get { home.routine.repetitions }
        set { home.routine.repetitions = newValue }
    }

    var restSeconds: Int {
        get { home.routine.restSeconds }
        set { home.routine.restSeconds = newValue }
    }

    var errorKey: String? {
        home.errorKey
    }

    func done() async {
        guard await home.saveRoutine() else {
            return
        }

        router.dismissSheet()
    }

    func save() async {
        _ = await home.saveRoutine()
    }

    // MARK: - Voice control

    var voiceEnabled: Bool {
        Self.voicePermissions.allSatisfy { permission in
            permissionService.status(for: permission) == .authorized
        }
    }

    var voiceFallback: VoicePermissionFallback? {
        guard let missing = Self.voicePermissions.first(where: { permission in
            permissionService.status(for: permission) != .authorized
        }) else {
            return nil
        }

        switch permissionService.status(for: missing) {
        case .denied:
            let messageKey = missing == .microphone
                ? "home.microphoneDenied"
                : "home.speechDenied"
            return .openSettings(messageKey: messageKey)
        case .restricted:
            return .restricted
        case .notDetermined, .unknown, .authorized:
            return .request
        }
    }

    func refreshPermissions() {
        permissionService.refresh()
    }

    func resolveVoiceAccess() async {
        refreshPermissions()

        switch voiceFallback {
        case .request:
            for permission in Self.voicePermissions {
                guard await permissionService.request(permission) == .authorized else {
                    break
                }
            }
        case .openSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            await UIApplication.shared.open(url)
        case .restricted, nil:
            break
        }
    }
}
