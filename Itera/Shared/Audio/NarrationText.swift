//
//  NarrationText.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import Foundation

/// Resolves the words a cue speaks, which may be shorter than the words it shows.
///
/// An optional `speak.<key>` entry in the String Catalog holds the spoken wording. Without one,
/// speech uses the displayed text. Recorded narration clips stay keyed by the base key, so a
/// spoken variant must only be added for a recorded language when the clip is regenerated.
enum NarrationText {
    static let spokenPrefix = "speak."
    private static let missing = "\u{0}"

    static func resolve(_ key: String, bundle: Bundle, locale: Locale) -> String {
        let spoken = bundle.localizedString(forKey: spokenPrefix + key, value: missing, table: nil)

        if spoken != missing, !spoken.isEmpty {
            return spoken
        }

        return String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale)
    }
}
