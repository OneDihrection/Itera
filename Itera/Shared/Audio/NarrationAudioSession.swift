//
//  NarrationAudioSession.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import AVFoundation

/// The single owner of the shared audio session, so every narrator, voice-over clip, count and
/// music track plays through the same route at the same loudness.
///
/// The app uses one configuration everywhere: `.playAndRecord` with `.default` mode and
/// `.defaultToSpeaker`. Switching between `.playback` (both speakers, loud) and `.playAndRecord`
/// (microphone open) made narration jump between loud and quiet depending on the screen and on
/// whether voice commands were listening, so the category no longer depends on listening.
/// `.voiceChat` is avoided because it plays like a phone call (much quieter, on the call volume).
///
/// Until microphone permission is granted the session uses `.playback` with `.spokenAudio`:
/// activating a recording category would otherwise trigger the permission prompt on its own.
enum NarrationAudioSession {
    /// Launch argument that restores `.voiceChat` while listening, to compare on a device.
    static let voiceChatComparisonArgument = "-IteraVoiceChatAudioMode"

    private static let lock = NSLock()
    private static var isActive = false
    /// Counts activation requests, so a deactivation scheduled earlier can tell that someone
    /// has needed the session since and must not switch it off under them.
    private static var activationRequests = 0

    // MARK: - Activation

    /// Configures the shared session, touching it only when something actually differs.
    ///
    /// Changing the category or reactivating while audio plays reconfigures the route and sample
    /// rate, which clicks and glitches music and narration. Every caller therefore asks for the
    /// same configuration, and repeated calls are no-ops apart from the speaker check.
    static func activate(allowsBluetoothMicrophone: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }

        activationRequests += 1
        let session = AVAudioSession.sharedInstance()
        let changed = try configureCategory(
            of: session,
            allowsBluetoothMicrophone: allowsBluetoothMicrophone
        )

        guard changed || !isActive else {
            enforceSpeakerIfNeeded(session)
            return
        }

        try session.setActive(true)
        isActive = true
        enforceSpeakerIfNeeded(session)

        #if DEBUG
        NSLog("Audio session configured category=%@", session.category.rawValue)
        #endif
    }

    /// The current activation count, captured when a deactivation is requested.
    static var activationToken: Int {
        lock.lock()
        defer { lock.unlock() }
        return activationRequests
    }

    /// Deactivates the shared session only if nothing activated it after `token` was taken.
    ///
    /// Deactivation that runs later on another queue (the listening worker) must not silence a
    /// narrator that started in between: the readiness check before a session stops listening
    /// just as the session's own audio starts, and a late deactivation left the whole session
    /// mute.
    static func deactivate(ifUnchangedSince token: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard activationRequests == token else {
            #if DEBUG
            NSLog("Audio session deactivation skipped: reactivated since it was requested")
            #endif
            return
        }

        deactivateSession()
    }

    /// Deactivates the shared session unconditionally, for an owner that is stopping all audio.
    static func deactivate() {
        lock.lock()
        defer { lock.unlock() }

        deactivateSession()
    }

    // MARK: - Route

    /// Call on every route change: when headphones or a Bluetooth device disconnect, a
    /// recording category can fall back to the quiet receiver instead of the loud speaker.
    static func handleRouteChange() {
        lock.lock()
        defer { lock.unlock() }

        guard isActive else {
            return
        }

        enforceSpeakerIfNeeded(AVAudioSession.sharedInstance())
    }

    // MARK: - Private

    /// Applies the app-wide category, returning true when it had to change.
    private static func configureCategory(
        of session: AVAudioSession,
        allowsBluetoothMicrophone: Bool
    ) throws -> Bool {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            let matches = session.category == .playback
                && session.mode == .spokenAudio

            if matches {
                return false
            }

            try session.setCategory(.playback, mode: .spokenAudio)
            return true
        }

        var options: AVAudioSession.CategoryOptions = [
            .defaultToSpeaker,
            .allowBluetoothA2DP,
        ]

        if allowsBluetoothMicrophone {
            options.insert(.allowBluetoothHFP)
        }

        let matches = session.category == .playAndRecord
            && session.mode == playAndRecordMode
            && session.categoryOptions.isSuperset(of: options)

        if matches {
            return false
        }

        try session.setCategory(.playAndRecord, mode: playAndRecordMode, options: options)
        return true
    }

    /// Moves output from the receiver to the built-in speaker. Headphones and Bluetooth
    /// outputs are left alone; `.defaultToSpeaker` alone does not cover every route change.
    private static func enforceSpeakerIfNeeded(_ session: AVAudioSession) {
        let onReceiver = session.currentRoute.outputs.contains { output in
            output.portType == .builtInReceiver
        }

        guard onReceiver, session.category == .playAndRecord else {
            return
        }

        do {
            try session.overrideOutputAudioPort(.speaker)

            #if DEBUG
            NSLog("Audio output moved from receiver to speaker")
            #endif
        } catch {
            NSLog("Audio speaker override failed: %@", error.localizedDescription)
        }
    }

    /// Callers hold `lock`.
    private static func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
    }

    private static var playAndRecordMode: AVAudioSession.Mode {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(voiceChatComparisonArgument) {
            return .voiceChat
        }
        #endif

        return .default
    }
}
