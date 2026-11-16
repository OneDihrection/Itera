<!-- Phase1-BreathingCountdown.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 1: Shared breathing rest and Countdown

Status: Not started. Back to the [overview](README.md).

## Goal

Replace the duplicated breathing machines with one `BreathingRest`, and add the shared `Countdown` type. This is the lowest-risk phase.

## Current state

- `GuidedSetBreathing` (`Activities/ArmRaise/ArmRaiseGuidance.swift:83`) and `OppositionRest` (`Activities/Fingers/OppositionGuidance.swift:130`) contain the same logic. Each is an integer `step` machine: 0 is the opening, steps 1–9 are three breaths of inhale, hold and exhale with minimums of 6, 2 and 3 seconds, and 10 is the closing. Each also has a `narrationFinished` flag and caps elapsed time at 0.2 s per tick.
- `RestBreath` (`Session/Models/SessionDurationClock.swift`) is a 6 s inhale and 3 s exhale cycle derived from the rest deadline.
- `LongRestBreath` (same file) runs 3/2/5/2 s cycles. `DailyPlanNextView` uses it, and this phase leaves it in place until Phase 9.

## Changes

- Add `Tuntun/Features/Therapy/Shared/SessionFlow/BreathingRest.swift`:

  ```swift
  struct BreathPhase: Equatable {
      enum Motion { case rise, hold, fall, rest }
      let cue: [NarrationLine]?
      let minimum: Double
      let maximum: Double?
      let motion: Motion
  }

  struct BreathingRest: Equatable {
      let phases: [BreathPhase]
      let gatedOnNarration: Bool
      let total: Double?        // timed set rest
      let maximumStep: Double   // 0.2 scripted, .infinity wall-clock
      var intensity: Double { get }
      var currentCue: [NarrationLine]? { get }
      var isFinished: Bool { get }
      mutating func tick(_ now: Double) -> Bool   // true when the phase changed
      mutating func narrationCompleted()
      mutating func suspend()
      static func scriptedSet(opensAfterFirstSet: Bool, prefix: String) -> Self
      static func timedSet(seconds: Double) -> Self
      static func long(scripted: Bool, prefix: String?, nextTitleKey: String?) -> Self   // used in Phase 9
  }
  ```

  Keep today's intensity formula exactly: `0.25 + 0.75 * (1 - cos(expansion * π)) / 2`.
- Add `SessionFlow/Countdown.swift` with `OnResume { restart, resume }`, `start`, `seconds`, `isFinished`, `takeAnnouncement` and `suspend`. Nothing uses it yet.
- Switch these callers to `BreathingRest`:
  - `SessionEngine`: the `guidedSetBreathing` and `restBreath` snapshot fields, and the tick at `SessionEngine.swift:567-603`.
  - `FingerSessionViewModel.scriptedRest` (created around lines 586 and 707).
  - The balance `restBreath` (`BalanceSessionViewModel.swift:66`).
- Delete `GuidedSetBreathing`, `OppositionRest` and `RestBreath`.

## Verification

- Build. Rest-related transcripts must match exactly: keys, order, phase-change times, and intensity samples to within 1e-9.
- On device: the scripted rest between arm-raise sets and between opposition sets, and a generic rest with its breathing ring.

## SYSTEM_DESIGN.md

Add a dated section, "Shared breathing rest", stating that the scripted short rests and the timed rest use one type and that their timings are unchanged.
