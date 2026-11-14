//
//  PoseBackend.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

// MARK: - Body

/// Which Vision request finds body joints. Every body exercise keeps reading 2D image
/// points, so switching never changes counting rules; 3D adds metric joint positions.
enum BodyPoseBackend: String, CaseIterable, Identifiable {
    /// `VNDetectHumanBodyPoseRequest`: 19 image points with per-joint confidence, several people.
    case vision2D
    /// `VNDetectHumanBodyPose3DRequest` (iOS 17): 17 joints in meters, all or none, one person.
    case vision3D

    static let storageKey = "tracking.bodyPoseBackend"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .vision2D:
            return "tracking.backend.vision2D"
        case .vision3D:
            return "tracking.backend.vision3D"
        }
    }

    /// The saved choice. Debug builds accept `-IteraBodyPose vision3D` to override it.
    static var saved: BodyPoseBackend {
        TrackingBackendStore.value(
            launchArgument: "-IteraBodyPose",
            storageKey: storageKey,
            fallback: .vision2D
        )
    }
}

// MARK: - Hand

/// Which detector finds the 21 hand joints for the finger camera.
enum HandPoseBackend: String, CaseIterable, Identifiable {
    /// `VNDetectHumanHandPoseRequest`: image points only.
    case vision
    /// MediaPipe Hand Landmarker: image points plus world landmarks in meters.
    case mediaPipe

    static let storageKey = "tracking.handPoseBackend"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .vision:
            return "tracking.backend.visionHand"
        case .mediaPipe:
            return "tracking.backend.mediaPipe"
        }
    }

    /// MediaPipe ships for iOS devices and Simulators only; Mac Catalyst builds leave it out.
    var isAvailable: Bool {
        switch self {
        case .vision:
            return true
        case .mediaPipe:
            #if canImport(MediaPipeTasksVision)
            return true
            #else
            return false
            #endif
        }
    }

    /// The saved choice. Debug builds accept `-IteraHandPose mediaPipe` to override it.
    static var saved: HandPoseBackend {
        let value: HandPoseBackend = TrackingBackendStore.value(
            launchArgument: "-IteraHandPose",
            storageKey: storageKey,
            fallback: .vision
        )

        return value.isAvailable ? value : .vision
    }
}

// MARK: - Storage

private enum TrackingBackendStore {
    static func value<Backend: RawRepresentable>(
        launchArgument: String,
        storageKey: String,
        fallback: Backend
    ) -> Backend where Backend.RawValue == String {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments

        if let index = arguments.firstIndex(of: launchArgument),
           arguments.indices.contains(index + 1),
           let value = Backend(rawValue: arguments[index + 1]) {
            return value
        }
        #endif

        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = Backend(rawValue: raw) else {
            return fallback
        }

        return value
    }
}
