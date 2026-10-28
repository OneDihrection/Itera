//
//  AppLanguage.swift
//  Itera
//
//  Created by dimaswisodewo on 29/10/2026.
//

import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case indonesian = "id"

    static var selected: AppLanguage {
        let saved = UserDefaults.standard.string(forKey: "app.language")
        return saved.flatMap(AppLanguage.init(rawValue:))
            ?? (Locale.preferredLanguages.first?.hasPrefix("id") == true ? .indonesian : .english)
    }

    /// Explicit resource selection also applies to strings rendered outside SwiftUI.
    var resourceBundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    var locale: Locale { Locale(identifier: rawValue) }
    var speechIdentifier: String { self == .indonesian ? "id-ID" : "en-US" }
}
