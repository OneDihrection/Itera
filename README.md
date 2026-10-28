<!-- README.md — Created by dimaswisodewo on 2026-10-28. -->

# Itera

An iPad therapy session with a fixed routine: five arm raises on each side, five elbow bends on each side, and one left-side reaching round. Activities run left first, with 15-second rests. Cup practice is excluded from this increment.

Generate the single application target with `xcodegen generate`, then open `Itera.xcodeproj`. Persistent project settings belong in `project.yml`. Validated toolchain: Xcode 27.0 (27A266a), XcodeGen 2.45.4. The deployment minimum remains iPadOS 17.

The application root constructs capture, audio, permission, and session-storage owners. An observable session model coordinates their events through a platform-independent session engine and independent movement/reach activities. Navigation uses the shared router. Domain rules and acceptance requirements are defined in [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md).

History is stored atomically under Application Support/Sessions. The active checkpoint contains routine configuration and completed results, never camera images, audio, landmarks, or calibration. An abandoned checkpoint is finalized as interrupted on launch. Summary files are immutable by session identity. File errors remain visible, with retry and explicit acknowledgment before proceeding without reliable history. Files use the installation's normal OS backup policy; no app-level cloud synchronization or backup exclusion is configured.

See [session verification](SESSION_VERIFICATION.md) for performed checks and outstanding acceptance work.
