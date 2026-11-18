<!-- Phase3-Suspension.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 3: Suspension

Status: Done 2026-11-18 (as amended below). Track: core, requires Phase 2. Back to the [overview](README.md).

## Goal

Give the session one suspension model, owned by the engine. Today "paused" lives in six layers. After this phase, view models report the facts that block resume instead of deciding it themselves.

Fixes bugs 2 and 6 from the [overview](README.md#known-bugs-confirmed-in-source-2026-11-16).

## Current state

- `SessionEngine` uses `pausedSince`, `waitingSince` and `suspensionSince`, and `beginSuspension`/`endSuspension` (≈ 995-1044). Deadlines are rebased in `endSuspension` (≈ 1018-1020).
- `SessionProgress.pause(at:)`/`resume(at:)` and `pausedAt` also rebase the rest deadline.
- Each activity keeps its own `suspended` flag.
- `record` resumes progress even while the camera is waiting (`SessionEngine.swift:790-796`).
- `TherapySessionViewModel` refuses resume unless `voiceReady`, `listening`, audio and saves are OK (≈ 261-266). It pauses on its own at startup (≈ 192), after a save failure (≈ 481), when going to the background (≈ 297-302), and from `blockReadiness`.

## As implemented (2026-11-18)

`Suspension` (`Therapy/Shared/SessionFlow/Suspension.swift`) separates **reasons** from **blockers**:

- Reasons (`pause`, `cameraWait`) freeze the session. Backgrounding and audio interruptions are pauses, because nothing behaves differently for them.
- Blockers (`voiceUnavailable`, `storageFailure`) only refuse Resume. A newly reported blocker pauses, as `blockReadiness` and a save failure did before.

The frozen interval stays open until the engine calls `end()`. This reproduces today's timing exactly, including the startup Resume that arrives while `cameraWaiting` is still initially true.

What changed in code:

- The engine handles `.blocked(_:_:)`.
- `TherapySessionViewModel.command(.resume)` calls `reportBlockers()` instead of refusing Resume itself.
- `blockReadiness`, `background()` and a failed save report blockers instead of sending `pause`.
- `SessionProgress` lost `pausedAt`, `pause` and `resume`. The engine shifts the rest deadline through `shiftRest(suspendedAt:resumedAt:)`.

Not done: `requiresVoice` (Balancing is not on the engine until Phase 8) and the `.lifecycle` event (backgrounding is a voice blocker plus the existing discontinuity). Views still read the view model's voice and save flags.

The original plan follows for reference.

## Changes

- Add `SessionFlow/Suspension.swift`:

  ```swift
  struct Suspension: Equatable {
      enum Reason: Hashable {
          case userPause, background, audioInterruption
          case cameraWait
          case voiceUnavailable, permissionMissing, storageFailure
      }
      private(set) var reasons: Set<Reason>
      private(set) var since: Double?
      var isActive: Bool { get }
      var blockers: Set<Reason> { get }
      var canResume: Bool { get }
      mutating func insert(_ reason: Reason, at time: Double) -> Bool
      mutating func remove(_ reason: Reason, at time: Double) -> Double?
  }
  ```

- `SessionEngine`:
  - Add `suspension`, and remove the three `*Since` fields.
  - When the session becomes suspended: send `.suspend` to the activity once, cancel speech, and freeze the stage.
  - When it becomes active again: rebase deadlines and the gate, then replay the stage cue with a new gate.
  - New events: `.blocked(Suspension.Reason, Bool)` and `.lifecycle(.background / .foreground)`.
  - Add `requiresVoice: Bool` to `init`. Guided and finger pass `true` (ADR-005); balance passes `false` in Phase 8.
  - Skip and stop must never remove a suspension reason.
- `SessionProgress`: remove `pausedAt`, `pause` and `resume`. The engine rebases the rest.
- `TherapySessionViewModel`:
  - Delete the resume gating in `command(_:)`.
  - Send `.blocked(...)` whenever voice, permission or storage state changes.
  - When going to the background, send `.lifecycle(.background)`.
  - A failed save sends `.blocked(.storageFailure, true)`.
- Snapshot: expose `suspension` and `canResume`. Pause and recovery views read these values.
- Recalibration is **not** a suspension reason. It stays a stage reset (completed in Phase 4).

## Verification

- Build. Transcripts must match, except for these intended differences:
  - Skip during a camera wait leaves the suspension active (bug 2).
  - Resume while voice is unavailable does nothing, and the snapshot reports the blocker (bug 6).
- Harness:
  - A camera wait during instruction, feedback and rest, followed by recovery: the deadlines are rebased and the cue replays with a new identity.
  - Pause during a camera wait, then readiness returns: the session stays paused until Resume.
- On device:
  - Background and foreground in every stage.
  - An incoming phone call (audio interruption).
  - Revoking microphone permission mid-session.
  - Disabling on-device recognition.

## SYSTEM_DESIGN.md

Add **ADR-010 — Single session flow model**, accepted on the merge date:

- The engine owns a single `Suspension`.
- View models report blockers as events; they do not decide whether resume is allowed.
- Stages carry their own data (completed in Phase 4).
- Countdown resume stays different per path: the guided countdown restarts (`Countdown.OnResume.restart`), the finger countdown continues (`.resume`). This is settled behaviour, not an open question.
- It refines §5 and §15 and supersedes nothing.
