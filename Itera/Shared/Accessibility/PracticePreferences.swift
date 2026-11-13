//
//  PracticePreferences.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

/// Presentation choices never change therapy timing or required voice readiness.
enum PracticePreferences {
    static let calmMode = "practice.calmMode"
    static let celebrationSounds = "practice.celebrationSounds"
    static let buttonSounds = "practice.buttonSounds"
    /// How Home and Progress address the patient. Stored only on this device; empty means no name.
    static let patientName = "practice.patientName"
    static let dailyPlanSide = "practice.dailyPlanSide"
    /// How much of each key repetition is saved; see `ReplayRecording`.
    static let replayRecording = "practice.replayRecording"
    /// What a saved video hides; see `VideoCensoring`.
    static let videoCensoring = "practice.videoCensoring"

    // Earlier settings, read only to carry a choice over when the new keys are missing.
    private static let legacyRecordsRepClips = "practice.recordsRepClips"
    private static let legacyCensorsFace = "practice.censorsFace"
    private static let legacyCensorsBackground = "practice.censorsBackground"

    static var replayRecordingLevel: ReplayRecording {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: replayRecording),
           let level = ReplayRecording(rawValue: raw)
        {
            return level
        }

        let recordedVideo = defaults.object(forKey: legacyRecordsRepClips) as? Bool ?? true
        return recordedVideo ? .video : .skeleton
    }

    static var videoCensoringChoice: VideoCensoring {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: videoCensoring),
           let choice = VideoCensoring(rawValue: raw)
        {
            return choice
        }

        let face = defaults.object(forKey: legacyCensorsFace) as? Bool ?? true
        let background = defaults.object(forKey: legacyCensorsBackground) as? Bool ?? true

        switch (face, background) {
        case (true, false):
            return .face
        case (false, true):
            return .background
        case (true, true):
            return .both
        case (false, false):
            return .none
        }
    }

    static var repClipPrivacy: RepClipPrivacy {
        videoCensoringChoice.privacy
    }
}

/// The caregiver's privacy level for key-repetition replays, from most to least private.
/// Per-repetition numbers (duration, angle or reached range) are kept at every level.
enum ReplayRecording: String, CaseIterable {
    /// No skeleton and no video.
    case off
    /// Skeleton replays only.
    case skeleton
    /// Skeleton replays and a censored video.
    case video

    var savesSkeletons: Bool {
        self != .off
    }

    var savesClips: Bool {
        self == .video
    }
}

/// What a saved video hides. Every choice except `none` hides something; `none` is an explicit
/// caregiver choice that the settings page warns about.
enum VideoCensoring: String, CaseIterable {
    case face
    case background
    case both
    case none

    var privacy: RepClipPrivacy {
        switch self {
        case .face:
            return RepClipPrivacy(blursFace: true, blursBackground: false)
        case .background:
            return RepClipPrivacy(blursFace: false, blursBackground: true)
        case .both:
            return RepClipPrivacy(blursFace: true, blursBackground: true)
        case .none:
            return RepClipPrivacy(blursFace: false, blursBackground: false)
        }
    }
}
