//
//  NarrationAudioSession.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import AVFoundation

/// The audio-session setup both narrators use, so their loudness rules cannot drift apart.
///
/// Narration plays at normal media volume in every exercise. While voice commands listen,
/// the session uses `.default` rather than `.voiceChat`: voice chat echo-cancels the
/// microphone but treats output like a phone call (much quieter, on the call volume).
/// Commands are a few English words and narration avoids them, so self-triggering is
/// unlikely; it still needs confirming on hardware.
enum NarrationAudioSession {
    /// Launch argument that restores `.voiceChat` while listening, to compare on a device.
    static let voiceChatComparisonArgument = "-IteraVoiceChatAudioMode"

    private static let lock = NSLock()
    private static var isActive = false
    /// Counts activation requests, so a deactivation scheduled earlier can tell that someone
    /// has needed the session since and must not switch it off under them.
    private static var activationRequests = 0

    /// Configures the shared session, touching it only when something actually differs.
    ///
    /// Changing the category or reactivating while audio plays reconfigures the route and sample
    /// rate, which clicks and glitches music and narration. A therapy session therefore asks for the
    /// same configuration throughout, and repeated calls are no-ops.
    static func activate(listening: Bool, allowsBluetoothMicrophone: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }

        activationRequests += 1
        let session = AVAudioSession.sharedInstance()
        var changed = false

        if listening {
            var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]

            if allowsBluetoothMicrophone {
                options.insert(.allowBluetoothHFP)
            }

            let matches = session.category == .playAndRecord
                && session.mode == listeningMode
                && session.categoryOptions.isSuperset(of: options)

            if !matches {
                try session.setCategory(.playAndRecord, mode: listeningMode, options: options)
                changed = true
            }
        } else {
            let matches = session.category == .playback && session.mode == .spokenAudio

            if !matches {
                try session.setCategory(.playback, mode: .spokenAudio)
                changed = true
            }
        }

        guard changed || !isActive else {
            return
        }

        try session.setActive(true)
        isActive = true
        #if DEBUG
        NSLog("Audio session configured listening=%@", listening.description)
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

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
    }

    /// Call when the owning service deactivates the session, so the next `activate` reactivates it.
    static func noteDeactivated() {
        lock.lock()
        isActive = false
        lock.unlock()
    }

    private static var listeningMode: AVAudioSession.Mode {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(voiceChatComparisonArgument) {
            return .voiceChat
        }
        #endif

        return .default
    }
}
