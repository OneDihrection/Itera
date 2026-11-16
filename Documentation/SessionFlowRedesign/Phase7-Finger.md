<!-- Phase7-Finger.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 7: Finger flow on shared session types

Status: Not started. Back to the [overview](README.md).

## Goal

Move finger session progression out of `FingerSessionViewModel` and into a rebuilt `FingerSessionEngine` that uses the shared flow types. Ship it as two pull requests.

Finger keeps its own engine, separate from `SessionEngine`, because:

- it uses different evidence (`HandEvidence`, the side stabiliser and its own staleness rules);
- it persists differently (`FingerSessionSummary`, checkpoint `restore(prior)`);
- it speaks through a different audio service (`GuidanceAudioService`, which speaks `NarrationLine`s).

Making the engine generic over these would be the framework that §3 and ADR-006 forbid.

## Current state

- `FingerSessionEngine.swift` is a thin wrapper with `paused` and `finished` booleans.
- `FingerActivity.swift`:
  - `FingerPhase` has the cases `baseline, target, range, rangeResult, demonstration, countdown, active, feedback, rest, finished`.
  - Sub-states live in flags (≈ lines 26-72).
  - One `remaining` value is the timer for feedback, countdown and rest (≈ 233-266).
- `FingerSessionViewModel.swift` (≈ 1332 lines) contains:
  - `tick()` (≈ 546-611) with the scripted rest and the countdown gate;
  - `receive` (≈ 421-517);
  - `updateGuidance`, `completeNarration` and `narrate` (≈ 696-791);
  - `canResume` and `recoveryPanelKey` (≈ 822-844);
  - `calibrationMessage`, a string that gates scoring (≈ 505);
  - nine `previousInstruction = ""` resets;
  - the 15 s "calibration needs help" timer (≈ 653-656).
- Finger countdown resume continues from where it stopped; the guided countdown restarts. **Keep this difference.**

## 7a. Domain pull request

- `FingerSessionEngine` becomes `handle(FingerSessionEvent) -> FingerSessionTransition`, holding `stage: SessionStage`, `suspension: Suspension` and `policy: GuidancePolicy`.
- `FingerActivity`:
  - Keeps only the phases `baseline, target, range, rangeResult, active`.
  - Emits `ActivityFact`s.
  - Deletes the flow phases and `remaining`.
- `OppositionGuidance` becomes `OppositionScript(side:)`, conforming to `GuidancePolicy`. The 3 s holds and the 5 s next-set countdown come from `policy.timing`.
- The countdown uses `Countdown(onResume: .resume)`.
- Error and recovery state becomes `Suspension` reasons. `FingerTrackingRecovery` reports `.cameraWait`. Camera delivery failure, voice, permission and storage problems become blockers.

  Detection loss must **not** pause the session ("Detection waits without automatic pause", 2026-11-16).
- Checkpoint restore and the calibration-help timer move into the engine.

## 7b. View-model pull request

- `FingerSessionViewModel` forwards only `.tick`, evidence, audio and lifecycle events, and maps the snapshot and effects.
- Delete:
  - `practiceCountdownReady`
  - all `previousInstruction` resets
  - the `calibrationMessage` gate
  - `completeNarration`
  - `canResume`, which is now read from the snapshot
  - `scriptedRest`
- `FingerSessionView` reads the stage from the snapshot.
- Overlay smoothing, recorder synchronisation and saving stay in the view model.

## Verification

- Build after each pull request.
- Finger transcripts must match:
  - opposition, left and right, at 2×5 and 3×3
  - a range exercise
  - forearm rotation
  - pause during the countdown (resumes where it stopped)
  - skipping rest
  - restore from a checkpoint in the middle of an exercise
- On device:
  - Hold-count timing.
  - Recovery after the camera fails (3 s, or 10 s at startup).
  - Recovery when voice becomes unavailable.
  - Hand loss without an automatic pause.
  - Save-for-later and resume.

## SYSTEM_DESIGN.md

- Add a dated section, "Finger flow on shared session types", explaining why there are two engines.
- Extend ADR-010.
