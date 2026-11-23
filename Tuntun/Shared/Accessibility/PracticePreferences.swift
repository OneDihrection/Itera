//
//  PracticePreferences.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

/// Presentation choices never change therapy timing or required voice readiness.
enum PracticePreferences {
    static let calmMode = "practice.calmMode"
    static let celebrationSounds = "practice.celebrationSounds"
    static let buttonSounds = "practice.buttonSounds"
    /// The earlier plan-wide training side; read only to carry it over to each exercise.
    static let dailyPlanSide = "practice.dailyPlanSide"
    /// Each exercise's training side (`RoutineSides`), keyed by its daily-plan item id.
    static func exerciseSide(_ itemID: String) -> String {
        "practice.side." + itemID
    }
    /// Each exercise's sets and repetitions, keyed by its daily-plan item id; missing keeps the
    /// program's own.
    static func exerciseSets(_ itemID: String) -> String {
        "practice.sets." + itemID
    }
    static func exerciseRepetitions(_ itemID: String) -> String {
        "practice.repetitions." + itemID
    }
    /// The plan-wide rest between sets, in seconds. Replaces the earlier per-exercise
    /// `practice.rest.<id>` values, which are no longer read.
    static let shortRestSeconds = "practice.shortRest"
    /// The plan-wide narrated breaths between exercises and between sides.
    static let longRestBreaths = "practice.longRestBreaths"
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
