<!-- Phase0-Baseline.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 0: Baseline transcripts

Status: Not started. Back to the [overview](README.md).

## Goal

Before any production change, record how every session path behaves today. Each later phase must reproduce these transcripts exactly, apart from the bug fixes it lists. This phase changes no production code.

## Harness

- Build a temporary harness outside the repository, in a scratch directory. Do not add it to `project.yml`, and do not add a test target.
- Compile it with `swiftc` against the logic files, which import only Foundation:
  - `Tuntun/Features/Therapy/Session/Models/**`
  - `Tuntun/Features/Therapy/Shared/**` (excluding `LivePose.swift`)
  - the Foundation-only files in `Tuntun/Features/Therapy/Activities/*/` (`grep -L 'import SwiftUI\|import UIKit\|import Combine'`)
  - `Tuntun/Features/Routine/Models/**`
  - the tracking models under `Tuntun/Shared/Tracking/Models`
- Add the domain types each phase introduces as they appear. The compile fails if a logic file imports anything other than Foundation.
- Feed scripted event sequences through the harness: synthetic `TrackingObservation` frames, ticks, commands, readiness changes, and narration completion and reading events. Use a fake clock.
- After each `handle` call, print one transcript line with the time, stage, suspension, instruction key, countdown seconds, rest phase and intensity, and the effects (speak/audio keys with their identity index, cancel, checkpoint, finalize, saveKeyReps, keepRepClip).
- Print identities as stable indices (`g1`, `g2`, …), not as UUIDs, so transcripts can be diffed.

## Scenarios (about 25)

| Area | Scenario |
|---|---|
| Guided, generic | Arm raise 1 set; elbow bend 2 sets with rest; directional reach 1 round; fold towel 1 towel; timed practice fallback |
| Guided, script | Indonesian arm-raise script, left and right, at 2×5 and at a custom 3×3 |
| Suspension | Camera wait during an instruction card, the opening, the countdown, practice, feedback and rest; pause and resume in each stage; background |
| Commands | Skip during instruction, practice and camera wait; stop during feedback; retry calibration; recalibration between sets (camera change during rest) |
| §15 | Complete without touch; completion callback delivered twice; pause during final feedback; stop at the completion boundary; retry after stale asynchronous work; skip during recovery; finish the final activity |
| Finger | Opposition scripted, left and right; a generic range exercise; pause during the countdown; skipping rest; restore from a checkpoint |
| Balance | Cross-midline, external rotation and sit-to-stand through their domain engines, plus a minimal transcript of the view model's opening and rest logic, transcribed by hand from `BalanceSessionViewModel` |
| Long rest | The `LongRestBreath` timeline plus the `DailyPlanNextView.nextStage` rules, copied into the harness, scripted and generic |

The finger and balance flows currently live in view models, and the long rest lives in a view. For these, record the domain-level transcript, and record the view-model or view rules as copied harness logic so that Phases 7 to 9 have a reference.

## Device reference

On the M1 iPad, record screen video with audio of:

- one Indonesian scripted arm-raise set and its short rest;
- one generic opening and countdown;
- one opposition set.

Later phases use these as the timing reference for narration joins.

## Output

- Harness source and transcripts stay outside the repository.
- Note the scratch location in your working notes, so later phases can find them.

## SYSTEM_DESIGN.md

None.
