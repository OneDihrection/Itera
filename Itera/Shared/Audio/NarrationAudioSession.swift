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

    static func activate(listening: Bool, allowsBluetoothMicrophone: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()

        if listening {
            var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]

            if allowsBluetoothMicrophone {
                options.insert(.allowBluetoothHFP)
            }

            try session.setCategory(.playAndRecord, mode: listeningMode, options: options)
        } else {
            try session.setCategory(.playback, mode: .spokenAudio)
        }

        try session.setActive(true)
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
