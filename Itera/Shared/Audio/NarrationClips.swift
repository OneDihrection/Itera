//
//  NarrationClips.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import Foundation

/// One spoken sentence, identified by its String Catalog key.
struct NarrationLine: Equatable {
    let key: String
    /// The number substituted into a format key such as "guide.holdDuration %lld".
    var argument: Int? = nil
}

/// Human-sounding narration recorded ahead of time and bundled with the app.
///
/// `Tools/generate_narration.py` renders sentences in Indonesian and English, while
/// `Tools/generate_marizka_counts.py` renders number takes in both languages, all in Marizka's
/// voice. `Tools/normalize_narration.swift` levels them as bundled AAC. Sessions stay offline:
/// nothing is synthesized over the network at runtime. A missing clip falls back to the
/// on-device system voice.
enum NarrationClips {
    static func url(for line: NarrationLine, language: AppLanguage) -> URL? {
        Bundle.main.url(forResource: resourceName(for: line, language: language), withExtension: "m4a")
    }

    /// A full-length Marizka number for repetition feedback and evidence-timed holds.
    static func countURL(_ number: Int, language: AppLanguage) -> URL? {
        Bundle.main.url(
            forResource: countResourceName(number, language: language, countdown: false),
            withExtension: "m4a"
        )
    }

    /// A separate short take that fits the existing one-second countdown clock.
    static func countdownURL(_ number: Int, language: AppLanguage) -> URL? {
        Bundle.main.url(
            forResource: countResourceName(number, language: language, countdown: true),
            withExtension: "m4a"
        ) ?? countURL(number, language: language)
    }

    static func countResourceName(_ number: Int, language: AppLanguage, countdown: Bool) -> String {
        let kind = countdown ? "countdown" : "repetition"
        return "marizka-\(language.rawValue)-\(kind)-\(number)"
    }

    /// The bundled file name for a line in one language, such as "narration-en-session.ready".
    /// Must match `clip_name` in Tools/generate_narration.py.
    static func resourceName(for line: NarrationLine, language: AppLanguage) -> String {
        var name = line.key.replacingOccurrences(of: " %lld", with: "")

        if let argument = line.argument {
            name += "-\(argument)"
        }

        let safe = name.unicodeScalars.map { scalar -> Character in
            isSafe(scalar) ? Character(scalar) : "_"
        }

        return "narration-\(language.rawValue)-" + String(safe)
    }

    private static func isSafe(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || ".-_".unicodeScalars.contains(scalar))
    }
}
