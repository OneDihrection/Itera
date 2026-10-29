//
//  VoiceCommandVocabulary.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

enum VoiceCommand: Equatable { case pause, resume, stop, repeatInstruction }

/// Exact short phrases only: ordinary sentences and command substrings do not activate controls.
struct VoiceCommandVocabulary {
    private let commands: [String: VoiceCommand]
    var contextualStrings: [String] { commands.keys.sorted() }

    init(
        pause: String = String(localized: "voice.command.pause"),
        resume: String = String(localized: "voice.command.resume"),
        stop: String = String(localized: "voice.command.stop"),
        repeatInstruction: String = String(localized: "voice.command.repeat")
    ) {
        var mapping: [String: VoiceCommand] = [:]
        for (command, phrases) in [
            (VoiceCommand.repeatInstruction, repeatInstruction), (.resume, resume), (.pause, pause), (.stop, stop)
        ] {
            for phrase in phrases.split(separator: "|") {
                let normalized = Self.normalize(String(phrase))
                if !normalized.isEmpty {
                    mapping[normalized] = command
                }
            }
        }
        commands = mapping
    }

    func command(in transcript: String) -> VoiceCommand? {
        commands[Self.normalize(transcript)]
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
