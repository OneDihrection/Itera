<!-- README.md — Created by dimaswisodewo on 2026-11-16. -->

# Session flow redesign

Status: **proposed, not implemented.** Revised 2026-11-18: Phases 0–4 are the core and Phases 5–9 are optional follow-ups. This folder is the plan for unifying the app's session state machines. Each phase has its own file with its scope and how to verify it. Read [SYSTEM_DESIGN.md](../../SYSTEM_DESIGN.md) in full before starting any phase (AGENTS.md). If this plan and SYSTEM_DESIGN.md disagree, SYSTEM_DESIGN.md wins until a phase updates it.

Decisions taken when planning:

- The redesign covers every session path: guided body therapy, finger, balance, and the daily-plan long rest.
- Scripted Indonesian narration (arm raise, thumb opposition) moves behind a guidance policy that is chosen once at session start.
- Every phase keeps behaviour unchanged, except for the bug fixes it lists.

Decisions added in the 2026-11-18 revision:

- **Phases 0–4 are the core milestone.** After Phase 4 the guided `SessionEngine` is a single-owner state machine: one `SessionStage` whose cases carry their own data, one `Suspension`, one `GuidanceGate` and one `record`. The redesign can stop there and leave nothing half-migrated. Phases 5–9 are independent, optional follow-ups. Each needs Phase 4, plus Phase 5 where its file says so.
- **Countdown resume stays different per path.** The guided countdown restarts after a resume, and the finger countdown continues from where it stopped. This is settled behaviour, recorded in ADR-010 when Phase 3 lands, and `Countdown.OnResume` keeps both options. It is no longer an open risk.
- **Bug 2 may land early.** A standalone fix ahead of Phase 3 is allowed: skip records the outcome and never lifts a suspension. It needs its own DesignLog entry, because the behaviour visibly changes.

## Why

Progression logic currently lives in **four separate engines**, and each handles pause, rest, countdown, narration gating and stale callbacks differently.

| Path | Where progression lives | Main problems |
|---|---|---|
| Guided body therapy | `Session/Models/SessionEngine.swift` (≈1045 lines), `SessionProgress.swift` | The engine is a reducer, `handle(event, at:) -> SessionTransition` (snapshot plus effects), which `TherapySessionViewModel` ticks every 50 ms. Its stage enum is only part of the state: two stage enums are kept in sync by hand (`SessionSnapshot.Stage`, `SessionProgress.Stage`), and about 30 private vars act as hidden sub-states. "Paused" lives in 6 layers. `deadline` means something different in each stage. Instruction strings such as `"calibration.complete"` are used as state. There are about 30 `usesArmRaiseScript`/`scriptedGuidance` branches across the engine and `MovementActivity`, plus more in views. The engine works out domain events by comparing old and new activity presentation. |
| Finger | `Activities/Fingers/FingerSessionViewModel.swift` (≈1396 lines) | A second progression machine runs on a 0.1 s timer in the view model: scripted rest (`OppositionRest`), countdown gate (`practiceCountdownReady`), speech watchdog, 9 `previousInstruction = ""` resets, a `calibrationMessage` string that gates scoring, and `canResume` built from 7 flags. |
| Balance | `Activities/Balance/BalanceSessionViewModel.swift` (≈1028 lines) | The view model owns the whole flow: an `OpeningCue` enum, sets, and rest as a `Task` loop that sleeps 1 s at a time. |
| Daily plan | `Features/Home/Views/DailyPlanNextView.swift` | An 11-stage long-rest machine as view `@State`, with an 80 ms polling `.task`, although `DailyPlanNextViewModel` now exists beside it. The 4 s completion auto-advance `Task.sleep` (`DailyPlanTiming.completionPreview`) is copied into three views. |

This breaks SYSTEM_DESIGN §3 and ADR-006 (original specification §3 and §15 in the design log) ("Activity view models … do not maintain another progression state machine").

### Known bugs (confirmed in source 2026-11-16, line references rechecked 2026-11-18)

| # | Bug | Location | Fixed in |
|---|---|---|---|
| 1 | The snapshot shows `.feedback` even when `progress.record` did nothing (its guard failed). | `SessionEngine.swift:808` | Phase 4 |
| 2 | Skipping during a pause or camera wait resumes progress or the activity, while the engine's wait state is still set. | `SessionEngine.swift:790-796` | Phase 3, or earlier as a standalone fix |
| 3 | `record` does not clear `deadline`, so a stale value can cut feedback short after a skip. | `SessionEngine.swift:786-825` | Phase 4 |
| 4 | The execution-identity check always passes: `record(execution: progress.executionID, …)`. | `SessionEngine.swift:802, 884` | Phase 4 |
| 5 | Stop copies the record logic. | `SessionEngine.swift:874-892` | Phase 4 |
| 6 | The view model decides whether resume is allowed and never tells the engine why it refused. It also pauses on its own, for example after a save failure. | `TherapySessionViewModel.swift:261-266, 481` | Phase 3 |
| 7 | There are four stale-callback schemes, four speech watchdogs, four countdowns and three rest implementations. `GuidedSetBreathing` and `OppositionRest` are copies of each other. | see phases | Phases 1, 2 (core); 5 (optional) |
| 8 | Instruction strings are used as state. | `SessionEngine.swift:202-204, 671, 687, 699`; `TherapyLightSession.swift:83-84`; `TherapySessionView.swift:235-236`; `FingerSessionViewModel.swift:143, 568, 738-739, 804` | Phases 5, 7 (optional) |

Stopping after the core leaves bug 8 and the countdown part of bug 7 in place. They are contained: the core does not rely on them.

## Target architecture

New shared types go in `Tuntun/Features/Therapy/Shared/SessionFlow/`. They are concrete, use Foundation only, and are not a generic state-machine framework. ADR-006 allows shared concrete primitives.

| Type | Replaces |
|---|---|
| `SessionStage`, where each stage carries its own data | `SessionSnapshot.Stage` + `SessionProgress.Stage`, `deadline`, `feedbackEnteredAt`, `cardIndex`, `guidancePlan`, `positioningPending`, `calibrationCompletionPending`, `awaitingCountdownGuidance`, `calibrationInvalidatedBetweenSets` |
| `Suspension` (a set of reasons) | `pausedSince`, `waitingSince`, `suspensionSince`, `progress.pausedAt`, the view models' `canResume`, finger error/pause flags, balance `paused` |
| `GuidanceGate` | `guidance`, `narrationComplete`, `readingComplete`, `speechTimeout`, `pendingScriptMovement`; finger `speechID`/`speechDeadline`/`spokenFlowKey`; balance `openingSpeechID`; long-rest `narrationID` |
| `Countdown` (added in Phase 5) | Four countdown implementations, `announcedCountdown`, `practiceCountdownReady`, Movement's `-1` sentinel |
| `BreathingRest` | `GuidedSetBreathing`, `OppositionRest` (Phase 1). `RestBreath` stays as the timed rhythm; `LongRestBreath` until Phase 9 |
| `ActivityFact` | The engine comparing presentations, and the `"calibration.complete"` string checks |
| `GuidancePolicy` (`GenericGuidance`, `ArmRaiseScript`, `OppositionScript`) | `usesArmRaiseScript`/`usesOppositionScript` branches, `MovementActivity.scriptedGuidance`/`waitingForGuidance` |
| `LongRest` | The `DailyPlanNextView` `@State` machine |

### Key shapes (sketch)

```swift
enum SessionStage: Equatable {
    case preparing
    case opening(Opening)      // cards and calibration narration; owns its gate and advanceAt
    case practice(Practice)    // execution: UUID, countdown: Countdown?, gate: GuidanceGate?, evidenceHeld
    case feedback(Feedback)    // execution, enteredAt, gate, advanceAt
    case rest(Rest)            // breathing: BreathingRest, next: .set | .activity
    case summary

    /// The only place that shifts deadlines after a suspension.
    mutating func rebase(by frozen: Double)
}

struct Suspension: Equatable {
    enum Reason: Hashable {
        case userPause, background, audioInterruption         // cleared only by explicit Resume
        case cameraWait                                        // clears itself when readiness returns
        case voiceUnavailable, permissionMissing, storageFailure  // blockers, cleared by events
    }

    var isActive: Bool { get }
    var canResume: Bool { get }

    /// Returns true when the session became suspended.
    mutating func insert(_ reason: Reason, at time: Double) -> Bool

    /// Returns the frozen duration when the session stopped being suspended.
    mutating func remove(_ reason: Reason, at time: Double) -> Double?
}

struct GuidanceGate: Equatable {
    // id, key, startedAt, watchdogAt, narrated, read, followUp
    var isOpen: Bool { get }
    mutating func complete(_ id: UUID, available: Bool) -> Bool   // false for stale or duplicate ids
    mutating func reading(_ id: UUID, done: Bool) -> Bool
    mutating func expired(at time: Double) -> Bool
    mutating func extendWatchdog(to seconds: Double)
    mutating func rebase(by frozen: Double)
}

struct Countdown: Equatable {
    enum OnResume { case restart, resume }   // guided restarts, finger resumes (current behaviour)
    mutating func start(at time: Double)
    func seconds(at time: Double) -> Int
    func isFinished(at time: Double) -> Bool
    mutating func takeAnnouncement(at time: Double) -> Int?   // each second announced once
    mutating func suspend()
}

enum ActivityFact: Equatable {
    case phaseEntered(ActivityStep)
    case calibrationCompleted
    case countdownRequested
    case repetitionCredited(Int)
    case targetReached
    case stepCompleted(StepKind)
    case cueChanged(String)
    case holdRemaining(Int)
}
// ActivityTransition gains `facts`.
// ActivityEvent gains .evidenceHeld(Bool, at:) and .countdownFinished(at:),
// and drops guidanceCompleted/countdownReady.

protocol GuidancePolicy {
    var timing: GuidanceTiming { get }   // countdown seconds per set, MovementTiming, watchdogs, gatesScoringOnNarration
    func opening(_ context: GuidanceContext, includePositioning: Bool) -> [(OpeningStep, Utterance)]
    func utterance(for fact: ActivityFact, _ context: GuidanceContext) -> Utterance?
    func countdownCue(_ context: GuidanceContext) -> Utterance
    func feedback(_ outcome: ActivityOutcome, count: Int, _ context: GuidanceContext) -> Utterance
    func rest(_ context: GuidanceContext, hasNextSet: Bool, restSeconds: Double) -> BreathingRest
    var longRestScript: LongRestScript? { get }
}
```

### Rules

- **The engine owns `Suspension`.** View models report facts as events: `.blocked(reason, Bool)` and `.lifecycle(.background / .foreground)`. They no longer decide whether resume is allowed or pause on their own. Balance passes `requiresVoice: false`.
- **Each stage owns its deadlines and gate.** Leaving a stage drops them, so stale fields cannot carry over. `record` reads the execution identity from `.practice`. Stop and skip share one `record(outcome)`. Skip never lifts a suspension.
- **Activities emit facts.** The engine stops comparing presentations. It owns a single `Countdown`, so countdown seconds are announced from one place instead of five.
- **Activities keep their own internal machines** (ADR-006). Script timing reaches them through `MovementTiming` in `init`, so activity code has no script flags.
- **The guidance policy is chosen once.** A factory switch next to the activity factory switch selects it from the frozen session language and the activity. The protocol has exactly three implementations; ADR-010 records a three-case enum with a `switch` as the alternative.
- **Balance runs on `SessionEngine`.** A `BalanceActivity: TherapyActivity` adapter wraps `any BalanceMovementEngine`, and a new `.balance(BalanceSnapshot)` presentation case is added. `SessionProgress` owns results, checkpoint and finalize, and `BalanceSessionLog` is removed.
- **Finger keeps `FingerSessionEngine`, rebuilt on the same flow types.** It differs in evidence (`HandEvidence`), persistence (`FingerSessionSummary`, checkpoint restore) and audio service (`GuidanceAudioService`). A generic engine would be the framework that §3 and ADR-006 forbid, so finger keeps its own engine. `FingerActivity` loses its flow phases (demonstration, countdown, feedback, rest) and its shared `remaining` timer.
- **The daily plan becomes an explicit enum.** `enum DailyPlanFlow { idle, intro, session, completionPreview(until:), longRest, dayComplete }` lives in `DailyPlanViewModel`. Sessions report `sessionEnded(SessionEndReport)` through `DailyPlanSessionReporting`, which replaces `markOppositionRest` and `markArmRaiseRest`. The plan view model owns the single 4 s preview.
- **The long rest moves to the domain.** `LongRest` is driven by the existing `DailyPlanNextViewModel`, which `HomeBuilder` builds. `DailyPlanNextView` only renders it.
- **Composition follows SYSTEM_DESIGN §4.** Feature builders (`TherapySessionBuilder`, `HomeBuilder`) build pages and view models, and receive services through their `…Dependency` protocol. Navigation state lives in the feature's router and reaches pages as a `…RouterProtocol`. `AppComponent` is never passed to feature code.

## Phases

Each phase is one pull request. It must build on its own and match the golden transcripts, apart from the listed fixes. Core phases run in order. Optional phases can be taken in any order once their requirements have landed.

| Phase | Track | Requires | File | Summary | Bugs fixed |
|---|---|---|---|---|---|
| 0 | Core | — | [Phase0-Baseline.md](Phase0-Baseline.md) | Temporary harness and golden transcripts | — |
| 1 | Core | 0 | [Phase1-BreathingCountdown.md](Phase1-BreathingCountdown.md) | One `BreathingRest` (`Countdown` moved to Phase 5). **Done.** | 7 (part) |
| 2 | Core | 1 | [Phase2-GuidanceGate.md](Phase2-GuidanceGate.md) | One narration/reading gate on every path. **Done.** | 7 (stale callbacks) |
| 3 | Core | 2 | [Phase3-Suspension.md](Phase3-Suspension.md) | One suspension model owned by the engine; ADR-010 | 2, 6 |
| 4 | Core | 3 | [Phase4-StagePayloads.md](Phase4-StagePayloads.md) | `SessionStage` carries its own data; split the engine. **Core milestone.** | 1, 3, 4, 5 |
| 5 | Optional | 4 | [Phase5-ActivityFacts.md](Phase5-ActivityFacts.md) | Activities emit facts; the engine owns the countdown | 8 (guided) |
| 6 | Optional | 5 | [Phase6-GuidancePolicy.md](Phase6-GuidancePolicy.md) | Scripts move behind `GuidancePolicy` | — |
| 7 | Optional | 6 | [Phase7-Finger.md](Phase7-Finger.md) | Finger engine and view model on the shared types | 8 (finger) |
| 8 | Optional | 6 | [Phase8-Balance.md](Phase8-Balance.md) | Balance runs on `SessionEngine` | — |
| 9 | Optional | 4 | [Phase9-DailyPlan.md](Phase9-DailyPlan.md) | `DailyPlanFlow`, `LongRest` | — |

Phases 7 and 8 need `GuidancePolicy` (Phase 6), which needs `ActivityFact` (Phase 5). Phase 9 needs only the shared `BreathingRest`, `Countdown` and `GuidanceGate` types from the core. Its `SessionEndReport` gets its long-rest script from the policy once Phase 6 has landed; until then, it gets it from the session's script side, as `markArmRaiseRest` does today.

## Conventions

- New files get an Xcode-style header with the actual author and creation date (AGENTS.md).
- View models are `@MainActor @Observable` and receive dependencies through an explicit `init`. Pages and view models are built only by their feature's builder (`TherapySessionBuilder`, `HomeBuilder`), never by `AppComponent` directly. Pages that navigate receive the feature router as a `…RouterProtocol`.
- Domain files import Foundation only. The harness build fails if a domain file imports anything else, which also enforces the `Models/` rule in SYSTEM_DESIGN §3.
- There is no test target. Harnesses are temporary and live outside the repository.
- Each phase updates the affected rules in SYSTEM_DESIGN.md and appends a dated entry to Documentation/DesignLog.md. ADR-010 lands in Phase 3 and is extended in Phases 6 to 8.

## Verification for every phase

1. Build:
   ```sh
   xcodegen generate
   xcodebuild -project Tuntun.xcodeproj -scheme Tuntun \
     -destination 'generic/platform=iOS Simulator' \
     IPHONEOS_DEPLOYMENT_TARGET=17.0 CODE_SIGNING_ALLOWED=NO build
   ```
2. Rerun the Phase 0 harness and compare its output with the golden transcripts. The only allowed differences are the phase's listed fixes.
3. Run the original specification's §15 scenarios (Documentation/DesignLog.md) as harness scripts:
   - Complete each activity without touch.
   - Deliver a completion callback twice.
   - Pause during the final feedback.
   - Stop at the completion boundary.
   - Retry after stale asynchronous work.
   - Skip during recovery.
   - Finish the final activity.

   Each scenario must produce exactly one saved outcome, the correct rest, and one summary. Also script a stop that arrives in the same turn as the repetition that completes the set, and narration completions that arrive late or twice.
4. Run the device checks listed in each phase file on the M1 iPad. A Simulator build never establishes physical-device acceptance.

## Risks

| Risk | Mitigation |
|---|---|
| Timing changes in narration-gated scripts (praise and its follow-up, scripted hold counts) | Compare transcripts exactly. `evidenceHeld` reproduces the current `waitingForGuidance` reset. Check both Indonesian scripts on the device in Phases 6 and 7. |
| Stopping after Phase 4 leaves the script branches, the presentation comparisons and the finger, balance and daily-plan machines as they are today | Accepted. They are isolated from the core, SYSTEM_DESIGN §3 already documents them, and each optional phase can be done on its own later. |
| Rest timing drifts when moving from deadlines to accumulated elapsed time | Use `maximumStep: .infinity` for wall-clock rests, and compare per-second values in the transcripts. |
| Large view-model edits hide behaviour changes | One activity or path per commit. Delete legacy code only after the transcripts match. |
| Balance regressions (sit-to-stand countdown, background invalidation, restart) | The adapter keeps sit-to-stand's countdown inside its engine. Remove `BalanceSessionLog` only after the saved output matches. |
| A policy protocol looks like a speculative abstraction (§3) | It has exactly three concrete implementations. The enum alternative is documented. |
