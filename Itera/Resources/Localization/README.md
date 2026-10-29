<!-- README.md — Created by dimaswisodewo on 28/10/2026. -->

# Localization

`Localizable.xcstrings` contains app text. `InfoPlist.xcstrings` contains system permission descriptions. Both catalogs were created by dimaswisodewo on 28/10/2026. English (`en`) is the development and fallback language; Indonesian (`id`) is supported. Select English or Bahasa Indonesia on Home. The selection is saved and applies to app text, narration, and counts; active sessions retain their language. Voice recognition and command phrases remain English (en-US) in both app languages. Therapy requires available English on-device recognition.

## Adding text

1. Write a descriptive, namespaced literal key: `Text("home.greeting")` or `String(localized: "home.greeting")`.
2. Build to extract the key, then enter English and Indonesian values in Xcode's catalog editor. Add a translator comment explaining context.
3. Search the exact key to find code references and its catalog entry. Verify both languages before delivery; missing entries can display raw keys.

Reusable SwiftUI controls accept `LocalizedStringKey` for localized text. Keep literal keys at call sites so Xcode can extract them. Do not use generated symbols, a manual key enum, or a custom localization wrapper.

Use interpolation and catalog plural variations for quantities, never concatenated translated fragments. Keep persisted identifiers and domain values independent of translated text. Localize accessibility labels, narration, and command phrases as those features are added. Future audio services must use the resolved app language and freeze it for an active session.

Permission keys must retain Apple's required names. English defaults also remain in project.yml. Do not recreate duplicate InfoPlist.strings sources; Xcode compiles the catalog into localized resources.

## Verification

Regenerate with `xcodegen generate`, build, and inspect the English and Indonesian compiled resources. Launch in each app language and check that translations appear instead of keys. Verify system permission prompts with fresh authorization on an iPad; a Simulator build alone does not establish physical-device acceptance.
