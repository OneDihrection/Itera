<!-- Phase4-StagePayloads.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 4: Stages carry their data

Status: Not started. Back to the [overview](README.md).

## Goal

Replace the two hand-synced stage enums and the multipurpose `deadline` with one `SessionStage`. Each stage owns its own deadlines and gate.

Fixes bugs 1, 3, 4 and 5 from the [overview](README.md#known-bugs-confirmed-in-source-2026-11-16).

## Current state

- `SessionSnapshot.Stage` (`SessionEngine.swift:34`) is assigned at about 16 sites. `SessionProgress.Stage` (`SessionProgress.swift:12`) is kept in sync by hand.
- One `deadline` serves the instruction quiet delay, the 8 s demonstration, the feedback minimum and the `preparationWait` digits (dispatched at ≈ 537-562).
- Companion flags: `feedbackEnteredAt`, `cardIndex`, `guidancePlan`, `positioningPending`, `calibrationCompletionPending`, `awaitingCountdownGuidance`, `calibrationInvalidatedBetweenSets`.
- `record` (786-825) and `.stop` (875-892) are copies, and the execution check is circular.
- Re-announcing a cue on resume is written three times (≈ 469-478, 863-871, 908-912).

## Changes

- Add `SessionFlow/SessionStage.swift`:

  ```swift
  enum SessionStage: Equatable {
      case preparing
      case opening(Opening)
      case practice(Practice)
      case feedback(Feedback)
      case rest(Rest)
      case summary
      mutating func rebase(by frozen: Double)
      var legacy: SessionSnapshot.Stage { get }   // keeps views unchanged until Phase 5
  }

  struct Opening: Equatable  { var step: OpeningStep; var gate: GuidanceGate; var advanceAt: Double? }
  struct Practice: Equatable { let execution: UUID; var countdown: Countdown?; var gate: GuidanceGate?
                               var evidenceHeld: Bool; var pendingCalibrationCue: Bool }
  struct Feedback: Equatable { let execution: UUID; let enteredAt: Double; var gate: GuidanceGate?; var advanceAt: Double? }
  struct Rest: Equatable     { var breathing: BreathingRest; let next: NextUnit }   // .set | .activity
  enum OpeningStep: Equatable { case card(Int, demonstration: Bool), calibrationIntro, scriptedPosition, scriptedStart, tryMovement }
  ```

- `SessionEngine`:
  - Remove `deadline` and the companion flags listed above.
  - Add one `record(_ outcome:)`, used by skip, stop, debug finish and completion.
    - It takes the execution identity from `.practice`.
    - It moves to `.feedback` only when `progress.record` returns `true`.
  - Add one `replayStageCue()` helper, used for resume and camera recovery.
- `SessionProgress`:
  - Remove `Stage`. Keep the index, set, execution, results and summary.
  - `record` returns `Bool`.
  - Replace `finishFeedback`/`tick`/`finishNarratedRest` with `advance(at:) -> NextUnit?`.
- Split `SessionEngine.swift` by responsibility into `SessionEngine.swift` (events, readiness, suspension), `SessionEngine+Opening.swift`, `SessionEngine+Practice.swift` and `SessionEngine+Rest.swift`. It stays the same type, with private helpers moved to `fileprivate` extensions only where the split needs it.
- `SessionSnapshot.stage` becomes `stage.legacy`. Views are not edited in this phase.

## Verification

- Build. Transcripts must match, except for these intended differences:
  - Skip during an instruction card: feedback now waits for its narration and its minimum before rest (bug 3).
  - A `record` that does nothing leaves the stage unchanged (bug 1).
  - An outcome from an old execution is ignored (bug 4).
- Run all §15 scenarios. Add a stop in the same turn as the repetition that completes the set: exactly one outcome and one summary.
- On device: a full two-set arm raise with Pause in every stage.

## SYSTEM_DESIGN.md

Extend ADR-010 with the stage data model, and note in §15 that `SessionProgress` no longer owns a stage.
