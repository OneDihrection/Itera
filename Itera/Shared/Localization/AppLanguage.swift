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

    /// UserDefaults key for an explicit language choice made in Settings.
    static let storageKey = "app.language"

    /// Bahasa Indonesia unless English was explicitly chosen, whatever the device language.
    static var selected: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .indonesian
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
