<!-- Phase5-ActivityFacts.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 5: Activity facts and engine-owned countdown

Status: Not started. Track: optional, requires Phase 4. Back to the [overview](README.md).

## Goal

Activities emit typed facts, and the engine owns the pre-practice countdown. This replaces two things:

- the engine comparing old and new activity presentations to work out what happened;
- instruction strings used as state.

Fixes bug 8 for the guided path.

## Current state

- `observation` (`SessionEngine.swift:326-442`) works out repetition, phase and target events by comparing presentations.
- Countdowns are announced from five places (≈ 169-181, 323, 390-393, 428-431, 469/863, 772).
- Each activity has its own countdown:

  | Activity | Countdown state |
  |---|---|
  | `MovementActivity` | `countdown: Double?`, with an unused `-1` check at ≈ 496 |
  | `DirectionalReachActivity` | `deadline` |
  | `FoldTowelActivity` | `countdownDeadline` |
  | `TimedPracticeActivity` | `countdown` |

- String checks:
  - `isCalibrationCompletionCue` (`SessionEngine.swift:202-204`, 671, 687, 699)
  - `TherapyLightSession.swift:83-84`
  - `TherapySessionView.swift:235-236`

## Changes

- `TherapyActivity.swift`:
  - `ActivityTransition` gains `facts: [ActivityFact]`.
  - `ActivityEvent` gains `.countdownFinished(at:)` and `.evidenceHeld(Bool, at:)`, and drops `countdownReady` and `guidanceCompleted`.
  - Add `SessionFlow/ActivityFact.swift`.
- Migrate **one activity per commit**, in this order: `MovementActivity`, `DirectionalReachActivity`, `FoldTowelActivity`, `TimedPracticeActivity`. Each one:
  - emits `.countdownRequested`, `.calibrationCompleted`, `.repetitionCredited`, `.phaseEntered`, `.targetReached`, `.stepCompleted`, `.holdRemaining`;
  - deletes its private countdown;
  - accepts `.countdownFinished`.
- Engine:
  - `.practice.countdown` holds `Countdown(onResume: .restart)`.
  - Per-second audio comes only from `takeAnnouncement`.
  - Delete the presentation-comparison code only after the last activity has migrated.
- Snapshot: add `calibrationCuePending: Bool` and `countdown: (seconds: Int, running: Bool)?`. The two views use these values instead of comparing strings. Delete `isCalibrationCompletionCue`.

## Verification

- Build. Countdown, repetition, target and towel-cue transcripts must match, including restart-and-re-announce after a pause during the countdown.
- On device: a two-minute arm-raise practice. Check §12 performance (preview cadence, `Session frame rejected as stale` frequency); facts must not add per-frame work.

## SYSTEM_DESIGN.md

Extend ADR-010:

- Activities report facts.
- The engine owns the countdown.
- Countdown durations and the resume-restart rule are unchanged.
