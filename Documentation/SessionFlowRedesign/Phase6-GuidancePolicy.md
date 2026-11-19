<!-- Phase6-GuidancePolicy.md — Created by dimaswisodewo on 2026-11-16. -->

# Phase 6: GuidancePolicy for guided activities

Status: Not started. Track: optional, requires Phase 5. Back to the [overview](README.md).

## Goal

Move the Indonesian arm-raise script out of the engine, `MovementActivity` and the views, and put it behind a guidance policy chosen once when each activity is selected.

## Current state

- `usesArmRaiseScript` branches in `SessionEngine.swift` at ≈ 195, 203, 207, 214, 229-259, 288, 383-412, 487-491, 512-519, 552-555, 567-579, 629, 637, 653, 665-685, 699, 767, 815-822 and 1011.
- `TherapySessionViewModel.swift:109` decides the language: `scriptedArmRaise: AppLanguage.selected == .indonesian`.
- `MovementActivity` has `scriptedGuidance`. Script mode switches it to 3 s dwells and a 5 s next-set countdown. (`waitingForGuidance` was removed on 2026-11-19.)
- Views branch on `usesArmRaiseScript` and `armRaiseNarrationPrefix`.
- `ArmRaiseGuidance.swift` and `Shared/ScriptedRepetitions.swift` hold the key tables.

## Changes

- Add `SessionFlow/GuidancePolicy.swift`:

  ```swift
  struct Utterance: Equatable {
      var lines: [CueLine]
      var followUp: String? = nil
      var interrupts = false
  }

  enum CueLine: Equatable { case key(String), count(Int), target, holdSecond(Int), countdown(Int) }

  struct GuidanceContext {
      let activity: SessionActivity
      let setNumber: Int
      let presentation: ActivityPresentation?
  }

  protocol GuidancePolicy {
      var timing: GuidanceTiming { get }
      func opening(_ context: GuidanceContext, includePositioning: Bool) -> [(OpeningStep, Utterance)]
      func utterance(for fact: ActivityFact, _ context: GuidanceContext) -> Utterance?
      func countdownCue(_ context: GuidanceContext) -> Utterance
      func feedback(_ outcome: ActivityOutcome, count: Int, _ context: GuidanceContext) -> Utterance
      func rest(_ context: GuidanceContext, hasNextSet: Bool, restSeconds: Double) -> BreathingRest
      var longRestScript: LongRestScript? { get }
  }
  ```

- Add `GenericGuidance`, holding today's non-script branches.
- `ArmRaiseGuidance` becomes `ArmRaiseScript(side:)`, conforming to `GuidancePolicy`. Keep the file's author header, and absorb `scriptedSummary`.
- The session receives `GuidanceMode` (`.generic` or `.scriptedIndonesian`) at `init` from the frozen language. One factory switch, next to the activity factory switch, picks the policy.
- `MovementActivity`:
  - Takes `MovementTiming` (dwell and capture seconds) in `init`.
  - Loses `scriptedGuidance`.
  - No narration gate is needed for arm raise: since *Body exercises do not wait for narration* (2026-11-19) its evidence never waits for a line, and the step-change reset of `last`/`lastValid` stays in `MovementActivity`.
- Remove from the engine and snapshot: `usesArmRaiseScript`, `armRaiseNarrationPrefix`, `pendingPrefix`, `lastScriptHoldCount`. Views read neutral fields instead (for example `cueStyle`, `countdownTitleKey`). `armRaiseScriptSide` for the long rest becomes `policy.longRestScript`.
- `TherapySessionViewModel` only maps an `Utterance` to `SessionAudioService`. The demo-step chime stays.

## Verification

- Build. Full arm-raise script transcripts must match exactly, left and right, at 2×5, 3×3, 1×1 and 2×8:
  - praise, then follow-up order
  - hold seconds from fresh evidence only
  - `countdown.next` at 5 s
  - summary keys
  - three gated breaths
- Generic transcripts unchanged. `ElbowBendActivity` still uses generic timing.
- On device: both Indonesian scripts end to end (compare with the Phase 0 recording), and the English arm raise.

## SYSTEM_DESIGN.md

- Extend ADR-010 with the guidance policy. Record the three-case enum with a `switch` as the rejected alternative.
- Update the "Recorded right arm-raise mapping" and "Scripted narration follows custom counts" sections to name `ArmRaiseScript`.
- Fix the stale `LeftArmRaiseGuidance` reference at line ≈ 1065.
