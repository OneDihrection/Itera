<!-- Phase2-GuidanceGate.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 2: GuidanceGate

Status: Not started. Track: core, requires Phase 1. Back to the [overview](README.md).

## Goal

Use one value type for narration identity, narration completion, reading completion and watchdog, on every path. This replaces four different stale-callback schemes.

## Current state

| Path | State | Watchdog |
|---|---|---|
| Guided | `SessionEngine` vars `guidance`, `narrationComplete`, `readingComplete`, `speechTimeout`, `guidanceStartedAt`, `pendingScriptMovement` (≈ lines 72-110); `announce` at 625-646; `completeGuidance` at 659-713 | 20 s, or the plan watchdog; 45 s for scripted and feedback |
| Finger | `FingerSessionViewModel` `speechID`, `speechDeadline`, `spokenFlowKey` (`completeNarration` ≈ 803, `narrate` ≈ 822) | `max(15, characters × 0.25)` |
| Balance | `openingSpeechID`/deadline (`BalanceSessionViewModel.swift` ≈ 554-575); 11 other `audio.speak(id: UUID(), …)` calls whose identities are never matched | 8 s |
| Long rest | `@State narrationID` in `DailyPlanNextView` (≈ 31, 97, 328) | 12 s |

## Changes

- Add `SessionFlow/GuidanceGate.swift`:

  ```swift
  struct GuidanceGate: Equatable {
      let id: UUID
      let key: String
      let startedAt: Double
      private(set) var watchdogAt: Double
      private(set) var narrated: Bool
      private(set) var read: Bool
      private(set) var unavailable: Bool
      var followUp: String?
      var isOpen: Bool { narrated && read }
      mutating func complete(_ id: UUID, available: Bool) -> Bool
      mutating func reading(_ id: UUID, done: Bool) -> Bool
      mutating func expired(at now: Double) -> Bool
      mutating func extendWatchdog(to seconds: Double)
      mutating func rebase(by frozen: Double)
  }
  ```

- `SessionEngine`:
  - Replace the narration variables with `gate: GuidanceGate?`. It stays a single field until Phase 4 moves it into stage data.
  - Move `pendingScriptMovement` into `gate.followUp`.
  - Keep the reach card behaviour where an "unavailable" completion extends the deadline (≈ 710-712).
- Finger view model: the speech identity and watchdog become a gate. After resolving the text, the view model reports its text-length estimate through `extendWatchdog`.
- Balance view model: the opening speech becomes a gate.
- Leave the long rest for Phase 9.

## Verification

- Build. Every speak/complete pair in the transcripts must match.
- New harness scripts:
  - A duplicate completion does nothing.
  - A completion that arrives after the next cue started does nothing.
  - Each watchdog fires at its current time.
- On device: Stop during narration, then Go; the next cue plays once.

## SYSTEM_DESIGN.md

Add a short dated section: one guidance gate per cue, stale and duplicate completions ignored, watchdog values unchanged.
