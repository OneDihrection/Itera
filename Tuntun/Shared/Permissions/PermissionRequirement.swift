//
//  PermissionRequirement.swift
//  Tuntun
//
//  Created by dimaswisodewo on 24/11/2026.
//

/// What stands between a set of permissions and use, judged over all of them at once so a
/// screen can name every refused permission together instead of one per trip to Settings.
enum PermissionRequirement: Equatable {
    case granted
    /// Managed by someone else; neither a prompt nor Settings can lift it.
    case restricted
    /// Some have never been asked; prompting them comes first so a later denial message is complete.
    case needsPrompt([AppPermission])
    /// Every refused permission, in `AppPermission` order.
    case denied([AppPermission])
    case unavailable

    @MainActor
    static func evaluate(
        _ permissions: [AppPermission],
        in permissionService: any PermissionServiceProtocol
    ) -> PermissionRequirement {
        let statuses = permissions.map { permission in
            (permission, permissionService.status(for: permission))
        }

        if statuses.contains(where: { $0.1 == .restricted }) {
            return .restricted
        }

        let unasked = statuses
            .filter { $0.1 == .notDetermined }
            .map(\.0)
        if !unasked.isEmpty {
            return .needsPrompt(unasked)
        }

        let refused = statuses
            .filter { $0.1 == .denied }
            .map(\.0)
        if !refused.isEmpty {
            return .denied(refused)
        }

        if statuses.contains(where: { $0.1 != .authorized }) {
            return .unavailable
        }

        return .granted
    }

    /// The message naming what is missing, or nil when nothing blocks or a prompt comes first.
    var messageKey: String? {
        switch self {
        case .granted, .needsPrompt:
            return nil
        case .restricted:
            return "home.restricted"
        case .unavailable:
            return "home.permissionUnavailable"
        case .denied(let refused):
            return Self.deniedMessageKey(Set(refused))
        }
    }

    /// One catalog entry per combination keeps each sentence natural in both languages; three
    /// permissions give only seven, so no runtime list formatting is needed.
    private static func deniedMessageKey(_ refused: Set<AppPermission>) -> String {
        let camera = refused.contains(.camera)
        let microphone = refused.contains(.microphone)
        let speech = refused.contains(.speechRecognition)

        switch (camera, microphone, speech) {
        case (true, true, true):
            return "home.allPermissionsDenied"
        case (true, true, false):
            return "home.cameraMicrophoneDenied"
        case (true, false, true):
            return "home.cameraSpeechDenied"
        case (false, true, true):
            return "home.voiceDenied"
        case (true, false, false):
            return "home.cameraDenied"
        case (false, true, false):
            return "home.microphoneDenied"
        default:
            return "home.speechDenied"
        }
    }
}
