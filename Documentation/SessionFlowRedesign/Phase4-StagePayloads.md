<!-- Phase4-StagePayloads.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 4: Stages carry their data

Status: Done 2026-11-18 (as amended below); the core milestone is complete. Track: core, requires Phase 3. Back to the [overview](README.md).

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

## As implemented (2026-11-18)

- `SessionStage` lives in `Therapy/Session/Models/SessionStage.swift`, beside the engine, because it maps to the guided session's `SessionSnapshot.Stage` (`presentation`). The cases are `.preparing`, `.opening(Opening)`, `.practice`, `.feedback(Feedback)`, `.rest(Rest)` and `.summary`. `Opening.Step` is one of `calibrationIntro`, `scriptedPosition`, `scriptedStart`, `card(index:demonstration:)` and `tryMovement`; its `advanceAt` replaces the old `deadline`. `Feedback` has `enteredAt`, `advanceAt` and `recalibrateBeforeNext`. `Rest` has `deadline` (timed), `breathing` (scripted) and `recalibrateBeforeNext`. `.practice` carries nothing yet: see the checklist below.
- `enter(_:)` does not clear the narration gate. A finished cue's gate deliberately outlives some stage changes: the Indonesian script's spoken hold seconds rely on it, and so does the `guidanceID` the view reads. The next `announce` replaces it.
- `SessionProgress` methods: `record(...) -> Bool` (no `execution:` parameter), `finishIfLastSet(date:)`, `advanceAfterRest() -> NextUnit`. `shiftRest` is gone; `SessionStage.rebase` shifts every deadline.
- The opening steps replace the string checks for `"calibration.intro"` and `"…calibration.position"`. `"calibration.complete"` remains for Phase 5.
- The engine stays one file with `// MARK:` sections. Splitting it into extension files would have widened about 30 private members.
- Bugs: 1 (a refused record leaves the stage unchanged) and 4 (the circular execution parameter is gone) cannot be reached any more. 3 was latent, because every route into feedback ends with a timed cue that cleared the stale deadline; it is now impossible by construction. 5 is fixed by the shared `recordResult`. None of these changes a transcript.

## Core milestone

This phase completes the core redesign. Once it merges, the guided engine is a proper state machine, and the redesign can stop here. Before merging, check that all of the following are true:

- `SessionProgress.Stage` is gone. `SessionProgress` keeps only the index, set, execution, results and summary. ✅
- No `deadline`, `feedbackEnteredAt`, `cardIndex` or `calibrationInvalidatedBetweenSets` field remains in `SessionEngine`. ✅ `guidancePlan` and `positioningPending` stay: they are per-activity and per-session guidance settings, not stage state. `calibrationCompletionPending` and `awaitingCountdownGuidance` stay until Phase 5, because they are the calibration-cue and countdown handshake that `ActivityFact` and `Countdown` replace.
- `stage` is assigned only in `enter(_:)`, which also mirrors it into `SessionSnapshot.stage`. ✅
- Suspension exists only as the engine's `Suspension` (Phase 3), and narration identity only as the engine's single `GuidanceGate` (Phase 2). ✅
- Skip, completion and the caregiver's activity commands go through `record(_:)`. Stop shares its `recordResult(_:)` and then finalizes. ✅
- Resume and camera recovery use `resumeAfterSuspension()` and `replayStageCue(timed:)`. ✅

What the core leaves in place, to be handled by the optional phases: presentation diffing and instruction strings as state (Phase 5), the arm-raise script branches (Phase 6), and the finger, balance and daily-plan machines (Phases 7–9).

## Verification

- Build. Transcripts must match, except for these intended differences:
  - Skip during an instruction card: feedback now waits for its narration and its minimum before rest (bug 3).
  - A `record` that does nothing leaves the stage unchanged (bug 1).
  - An outcome from an old execution is ignored (bug 4).
- Run all §15 scenarios. Add a stop in the same turn as the repetition that completes the set: exactly one outcome and one summary.
- On device: a full two-set arm raise with Pause in every stage.

## SYSTEM_DESIGN.md

- Extend ADR-010 with the stage data model, and note in §15 that `SessionProgress` no longer owns a stage.
- In §3, update the `SessionEngine` row of Responsibilities so it names `SessionStage`, `Suspension` and `GuidanceGate`. Update the paragraph on the finger and Balancing machines to say that the redesign's core is complete and that Phases 5–9 remain optional.
