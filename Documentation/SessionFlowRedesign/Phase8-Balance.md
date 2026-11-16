<!-- Phase8-Balance.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 8: Balance on SessionEngine

Status: Not started. Back to the [overview](README.md).

## Goal

Run balance sessions on `SessionEngine` through an activity adapter. Afterwards, `BalanceSessionViewModel` only maps snapshots to presentation and coordinates services.

## Current state

- `BalanceSessionViewModel.swift` (≈ 997 lines) owns:
  - `OpeningCue` (≈ 30);
  - `practiceCountdown` and `countdownDeadline`;
  - `setNumber` and `setResults`;
  - the rest `Task` loop that sleeps 1 s at a time (≈ 285-312);
  - `paused` and camera waiting;
  - `advanceOpeningIfReady` (≈ 535-572), `updateCalibrationTransition` (≈ 591-619) and `completeOpeningCue` (≈ 621-642);
  - 11 `isSitToStand` branches;
  - `background()`, which sets `paused` directly (≈ 461).
- `BalanceMovementEngine` (`Balance/Domain/Models/BalanceMetrics.swift:116`) has `consume(_:scoringEnabled:)`, `invalidateCalibration()`, `restart()` and `nextSet()`. Its implementations are `CrossMidlineBalanceEngine`, `ArmMovementEngine` and `SitToStandBalanceEngine`.
- Balance already uses `TrackingObservation`, `SessionRepository`, `SessionCheckpoint` and `SessionSummary`. `TherapyKind` already has the balance cases, which `SessionEngine.selectActivity` currently maps to `nil`.

## Changes

- Add `Activities/Balance/Domain/Logic/BalanceActivity.swift`, a `TherapyActivity` that wraps `any BalanceMovementEngine`:
  - An observation calls `consume(frame, scoringEnabled: !evidenceHeld)`. The skeleton stays visible while scoring is held.
  - `.recalibrate` calls `invalidateCalibration()`, and `.nextSet` calls `nextSet()`.
  - Entering reaching, holding or returning emits `.calibrationCompleted`. A change in `completedTouches` emits `.repetitionCredited`. `.complete` produces `.finished`.
  - Sit-to-stand's seated countdown is part of its hold rule, so it stays inside its engine and its presentation.
- `ActivityPresentation` gains `.balance(BalanceSnapshot)`.
- `SessionEngine.selectActivity` maps the balance kinds to `BalanceActivity`. The session is built as a one-activity `Routine` with the configured sets and rest, and `requiresVoice: false`.
- `GenericGuidance` adds a balance opening script: intro, try, complete, countdown cue, a 3 s countdown and an 8 s watchdog. Rest uses `BreathingRest.timedSet`.
- `BalanceSessionViewModel`:
  - Delete `OpeningCue`, `practiceCountdown`, the `restTask` loop, `paused`, and `setNumber`/`setResults` (read them from the snapshot).
  - Keep `restart()`, which starts a new session.
  - Keep the rule that backgrounding during rest keeps calibration.
- Delete `BalanceSessionLog` only after the saved checkpoint, summary and key repetitions match today's output.

## Verification

- Build. Golden transcripts must match for cross-midline, external rotation and sit-to-stand: opening, calibration, countdown, sets and rest.
- The saved checkpoint, summary and `.reps.json` keep the same shape. Compare a decoded summary from before and after.
- On device: all three exercise families, pause during rest, background during rest and during practice, restart after completion, and that a voice failure does not block resume.

## SYSTEM_DESIGN.md

- Add a dated section, "Balance on the session engine".
- Update "Shared exercise screens: Balancing sets and rest" and "Balancing sessions" to name the adapter.
- Extend ADR-010.
