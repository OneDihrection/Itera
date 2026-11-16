<!-- Phase9-DailyPlan.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 9: Daily plan flow and long rest

Status: Not started. Back to the [overview](README.md).

## Goal

Make the daily-plan flow an explicit enum, and move the long-rest machine out of the view into a domain type driven by a view model.

## Current state

- `DailyPlanViewModel` (≈ 52-59) tracks its flow in six loose variables: `isRunning`, `restingBeforeNext`, `currentIndex`, `pendingArmRaiseSide`, `oppositionRestSide` and `armRaiseRestSide`. `finish` (≈ 505-535) has special handling for the arm-raise sides.
- `DailyPlanNextView.swift`:
  - an 11-stage `Stage` enum as `@State` (≈ 20-31);
  - `runTransition()`, which polls every 80 ms (≈ 118-192);
  - `nextStage` (≈ 194-214);
  - a 12 s narration fallback (≈ 198);
  - `plan.launchAfterRest` (≈ 154).
- The 4 s completion auto-advance appears in three views: `BalanceSessionView.swift:77-82`, `FingerSessionCompleteView.swift:53-64` and `TherapySessionView.swift:154`.
- Views call `plan.markOppositionRest` (`FingerSessionView.swift:41`) and `plan.markArmRaiseRest` (`TherapySessionView.swift:123`).

## Changes

- `DailyPlanViewModel`:

  ```swift
  enum DailyPlanFlow: Equatable {
      case idle
      case intro(index: Int, arm: TherapySide?)
      case session(index: Int, arm: TherapySide?)
      case completionPreview(index: Int, report: SessionEndReport, until: Double)
      case longRest(next: Int, arm: TherapySide?, script: LongRestScript?)
      case dayComplete
  }

  struct SessionEndReport: Equatable {
      let completed: Bool
      let longRestScript: LongRestScript?
  }
  ```

  - Sessions report `sessionEnded(_:)`, built from `policy.longRestScript`.
  - Views report `sessionReadyToLeave()` once saving finishes, and `scenePhase(_:)`.
  - The plan view model owns the single 4 s preview.
- Add `Features/Home/Domain/Models/LongRest.swift`, an enum that runs `.breathing(BreathingRest.long(...))`, then `.countdown(Countdown(total: 10))` or `.handOff` for scripted next items. It reproduces:
  - the "N napas lagi" lead line;
  - `inhaleLast`;
  - the silent scripted hold;
  - the 2 s minimum and 12 s maximum for narrated stages.
- Add `LongRestViewModel` (`@MainActor @Observable`), built by `AppDependencies.makeLongRest…`. It ticks every 80 ms through a Combine `Timer` publisher, subscribes to audio events, and handles pause and the scene phase. `DailyPlanNextView` only renders it.
- Remove the three 4 s `Task.sleep` copies, `markOppositionRest`, `markArmRaiseRest` and `LongRestBreath`.

## Verification

- Build. Long-rest transcripts must match, scripted and generic: phase timings, the narration-boundary gate, the 12 s maximum, pause, and the next-exercise title.
- On device, a full plan: opposition, then long rest, then arm raise left, then long rest, then arm raise right, then the next item. Also check:
  - pause during the long rest;
  - background during the completion preview;
  - ending the plan during rest (no launch);
  - a Debug custom-count plan.

## SYSTEM_DESIGN.md

- Update "Daily plan and Beranda", "Rest between daily-plan exercises" and "Scripted long-rest clip alignment" to describe `DailyPlanFlow` and `LongRest`.
- Mark the redesign complete in the "Session flow redesign" section.
