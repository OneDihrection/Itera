//
//  PermissionManager.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import AVFoundation
import Observation
import Speech

enum AppPermission: CaseIterable, Hashable {
    case camera
    case microphone
    case speechRecognition
}

enum PermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown
}

@MainActor
protocol PermissionManaging: AnyObject {
    func status(for permission: AppPermission) -> PermissionStatus
    func request(_ permission: AppPermission) async -> PermissionStatus
    func refresh()
}

/// Owns authorization only; capture and audio services retain runtime readiness checks.
@MainActor
@Observable
final class PermissionManager: PermissionManaging {
    private var statuses: [AppPermission: PermissionStatus] = [:]

    @ObservationIgnored
    private var pending: [AppPermission: Task<PermissionStatus, Never>] = [:]

    @ObservationIgnored
    private var promptTail: Task<PermissionStatus, Never>?

    init() {
        refresh()
    }

    func status(for permission: AppPermission) -> PermissionStatus {
        statuses[permission] ?? .unknown
    }

    func refresh() {
        for permission in AppPermission.allCases {
            statuses[permission] = Self.readStatus(permission)
        }
    }

    func request(_ permission: AppPermission) async -> PermissionStatus {
        if let task = pending[permission] {
            return await task.value
        }

        let predecessor = promptTail
        let task = Task { @MainActor in
            // Chain prompts across permission types, then recheck after any wait.
            _ = await predecessor?.value
            if Self.readStatus(permission) == .notDetermined {
                await Self.requestSystemPermission(permission)
            }
            let result = Self.readStatus(permission)
            self.statuses[permission] = result
            return result
        }
        pending[permission] = task
        promptTail = task
        let result = await task.value
        pending[permission] = nil
        if pending.isEmpty {
            promptTail = nil
        }
        return result
    }

    private static func readStatus(_ permission: AppPermission) -> PermissionStatus {
        switch permission {
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .unknown
            }
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .undetermined: return .notDetermined
            case .granted: return .authorized
            case .denied: return .denied
            @unknown default: return .unknown
            }
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .unknown
            }
        }
    }

    private static func requestSystemPermission(_ permission: AppPermission) async {
        switch permission {
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { _ in
                    continuation.resume()
                }
            }
        case .speechRecognition:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in
                    continuation.resume()
                }
            }
        }
    }
}
