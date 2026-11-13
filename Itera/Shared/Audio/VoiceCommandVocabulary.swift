//
//  VoiceCommandVocabulary.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

/// The only spoken commands: "stop" pauses and "go" resumes. Every other control is touch-only.
enum VoiceCommand: Equatable {
    case pause
    case resume
}

/// Exact short phrases only: ordinary sentences and command substrings do not activate controls.
///
/// Phrases resolve from the English string table in both app languages, because recognition is en-US only.
struct VoiceCommandVocabulary {
    private let commands: [String: VoiceCommand]
    var contextualStrings: [String] { commands.keys.sorted() }

    init(
        pause: String = String(localized: "voice.command.pause", bundle: Self.englishBundle),
        resume: String = String(localized: "voice.command.resume", bundle: Self.englishBundle)
    ) {
        var mapping: [String: VoiceCommand] = [:]

        for (command, phrase) in [(VoiceCommand.pause, pause), (.resume, resume)] {
            let normalized = Self.normalize(phrase)

            if !normalized.isEmpty {
                mapping[normalized] = command
            }
        }

        commands = mapping
    }

    func command(in transcript: String) -> VoiceCommand? {
        commands[Self.normalize(transcript)]
    }

    private static var englishBundle: Bundle {
        guard
            let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return .main
        }

        return bundle
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
