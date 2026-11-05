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
/// `Tools/generate_narration.py` renders each Indonesian narration string once with
/// ElevenLabs, and `Tools/normalize_narration.swift` levels it to a clear, even loudness
/// as AAC under `Resources/Audio/NarrationID`. Sessions stay offline:
/// nothing is synthesized over the network at runtime. A missing clip, or any other
/// language, falls back to the on-device system voice.
enum NarrationClips {
    /// Only Indonesian narration is recorded; English keeps the system voice.
    static let recordedLanguage = AppLanguage.indonesian

    static func url(for line: NarrationLine, language: AppLanguage) -> URL? {
        guard language == recordedLanguage else {
            return nil
        }

        return Bundle.main.url(forResource: resourceName(for: line), withExtension: "m4a")
    }

    /// The bundled file name for a line. Must match `clip_name` in Tools/generate_narration.py.
    static func resourceName(for line: NarrationLine) -> String {
        var name = line.key.replacingOccurrences(of: " %lld", with: "")

        if let argument = line.argument {
            name += "-\(argument)"
        }

        let safe = name.unicodeScalars.map { scalar -> Character in
            isSafe(scalar) ? Character(scalar) : "_"
        }

        return "narration-id-" + String(safe)
    }

    private static func isSafe(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || ".-_".unicodeScalars.contains(scalar))
    }
}
