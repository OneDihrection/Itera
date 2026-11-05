<!--
CognitiveUsability.md
Created by Amelia Putri Aftiana on 29/10/2026.
-->

# Cognitive usability in practice

Reference: [W3C Making Content Usable, Appendix A](https://www.w3.org/TR/coga-usable/#appendix1).
This is an implementation record, not a claim of WCAG or COGA conformance.

| COGA objective | Implementation |
| --- | --- |
| Understand the interface | Existing shared typography, native settings, named controls and consistent placement remain in use. |
| Find what is needed | Comfort settings are available from Home through the shared router. |
| Understand content | Guidance retains its short action and supporting cue. Exercise name, trained side and sequence position now remain visible in full-screen stages and pauses. English and Indonesian strings are provided. |
| Prevent mistakes | Tracking acceptance and freshness checks remain immediate. Presentation delays never allow repetitions from missing evidence. |
| Maintain attention | Calm display removes decorative rest and celebration motion. Button sounds can be disabled separately. System Reduce Motion remains respected. |
| Reduce memory demands | Temporary camera waits preserve the current stage, example and controls instead of replacing them with a recovery screen. The timer remains owned by the engine. |
| Help and support | Existing help, repeat instruction and explicit resume remain available; permission and voice failures retain their recovery controls. |
| Adapt to the user | Comfort choices persist. Full-screen control layout stacks at accessibility text sizes. |

## Tracking presentation

The finger session stops accepting evidence immediately when the hand is missing. Its large camera hint appears after 600 ms of continuous loss. Once shown, it clears after 250 ms of stable recovery. Missing evidence no longer incorrectly tells the user they showed the wrong hand. Camera resource failures still surface immediately.

The arm session no longer changes full-screen presentation solely because `cameraWaiting` changes. Its reserved camera-status slot reports the wait, while the session engine still suspends timing and scoring according to its existing readiness rules. Instruction, demonstration and countdown surfaces use the same dark background as the rendered example.

## Verification

- XcodeGen generation and Debug Simulator build.
- Temporary deterministic replay compiled the actual finger view model and domain files against platform service stubs: ten single-frame losses produced zero large-hint visibility changes; sustained loss showed the hint; stable recovery cleared it. Missing frames never reported tracking ready.
- Simulator inspection of the Indonesian comfort sheet and a detached instruction fixture confirmed labels, side, sequence position and help/pause controls. Fixtures do not start capture, recognition or persistence. Temporary fixture root changes were removed.
- Physical iPad acceptance remains pending: intermittent occlusion, sustained loss, wrong hand, camera interruption, English voice commands during narration, repeated recovery, Dynamic Type, VoiceOver, and rest/celebration preferences.
- Validate comprehension, comfort and pacing with stroke survivors and people with cognitive or learning disabilities. Those sessions may identify further changes; this work does not replace that testing.

[HandRise's official listing](https://apps.apple.com/us/app/handrise-hand-recovery/id6761848298) was reviewed as a product reference. Its public listing cannot establish animation performance or transition timing; no claim of matching its motion is made.

## Finger guidance and pause follow-up

- Voice and touch pause share `handleCommand`. Paused state presents the shared router's `fingerPause` sheet; Resume dismisses it. Sheets are hosted above the current full-screen cover. The arm flow also prioritizes its paused panel over voice-recovery content.
- Finger demonstrations now show a ten-second countdown. The domain owns it, including pause/camera-wait suspension and narration completion gating.
- Hand and finger bubbles use the existing aspect-fit/mirrored landmark mapping. Timer rings reflect accepted dwell, and checkmarks reflect the current calibrated movement target. They do not establish physical fingertip contact or grip force. Thumb/target labels are offset with leader lines to remain distinct when tips approach.
- New achievements present individually in catalog order. Each acknowledgment persists only the displayed ID; a storage failure leaves it visible. Each new badge starts its own bounded reveal and optional existing completion chime. A separate comfort setting disables achievement sounds. New installations show decorative motion by default following the user's request; saved Calm display choices and system Reduce Motion remain respected.
- Verification: actual view-model/domain replay covered recognized pause/resume events, repeated pause, ten-second countdown/camera-wait freezing, and per-award acknowledgment/duplicate activation. Simulator presentation with temporary in-memory fixtures confirmed pause sheet above the session, Resume dismissal, touch pause, and the badge sequence 1 → 3 → 5 with final dismissal. Temporary fixture dependencies and root changes were removed before the final build. Microphone recognition and live fingertip tracking still require physical-device checks.

## Indicator distinction (2 November 2026)

Full fist and hook fist use one transparent enclosing circle sized from the visible hand's aspect-fit bounds. Coordination exercises use fingertip circles only, without a wrist circle or offset fingertip labels. Numeric time and timed ring progress are supplied only during a valid instruction hold; they disappear during demonstration, countdown, rest, feedback, pause, or missing tracking. These are presentation changes; hold acceptance and repetition counting remain unchanged.

## Movement-only clock (2 November 2026)

The visible bubble clock now reports observed movement time instead of stable-hold time. `FingerMotionGuide` accumulates fresh intervals only when the current finger metric changes toward the instructed pose beyond a small spatial deadband. Its spatial anchor permits slow movement; stationary samples, small jitter, reverse movement and gaps contribute no time. The clock freezes while idle and resets at the next instruction leg. Suspension clears its sampling anchor without inventing elapsed time. Existing calibration holds, evidence acceptance and repetition rules remain unchanged.

Fingertip indicators increased to 108 points when active and 72 points otherwise. Stroke widths are 10 points for fingertips and 14 points for the enclosing hand circle; the hand circle has a 220-point minimum and extra padding. Time digits use larger bold typography. A temporary domain replay verified idle, jitter, direction, slow movement and tracking-gap behavior, and the Debug Simulator build passed. Live camera noise and placement remain physical-device checks.

## Ring/progression synchronization fix (2 November 2026)

A replay reproduced target acceptance while the separate movement-only indicator still displayed zero seconds. That visual clock has been removed: the circle now renders the activity's actual accepted-hold elapsed time, remaining time and completion endpoint. Finger start/target/return holds consistently require two seconds, replacing the earlier 250 ms finger practice acceptance. A wrong calibration target clears its hold immediately. The accepted endpoint publishes a full ring before the next observation starts a new leg. This supersedes the movement-only clock described above: holding still is counted only as part of the currently requested, valid pose; idle outside that pose never counts toward target acceptance.

The temporary replay passed wrong-pose, full-ring-before-acceptance, missing-evidence reset and return-completion cases. The Debug Simulator build passed after XcodeGen regeneration. Physical camera and pacing checks remain pending; no device acceptance is claimed from these checks.

## Completed-circle presentation gate (2 November 2026)

A second replay exposed the missing calibration path: the activity changed instructions and reset its hold before publishing a full-ring snapshot. Separately, a fresh 180 ms camera cadence repeatedly reset the earlier 150 ms hold-gap rule. The activity now accumulates fresh observed intervals up to the existing 300 ms freshness boundary and uses distinct entry/exit bands for small finger-pose boundary noise. Missing evidence, a genuine gap, pause or recalibration still clears pending holds.

A completed hold stays on its existing instruction with elapsed = duration, remaining = 0 and a unique completion identity. No observation or tick may advance it until the visible bubble reports the matching full-ring cue. The design system provides a cancellable 250 ms presentation settle; the session engine remains the progression owner. Old/duplicate callbacks cannot complete a new instruction. Narration finishes before a timed hold starts, and any replayed narration must also finish before pending progression commits. Both the spoken duration and the extra hold cue use the activity's duration.

The displayed decimal rounds upward so 0.0 can never appear for a partially completed circle. Partial arc updates animate smoothly; the final arc renders full immediately, then remains visible before advancement. Hand and fingertip circles stay inside the preview. The selected extension fingertip must be visible to present its cue, with existing camera guidance for recovery.

Verification: the original replay changed from two failures to passes. Additional actual-domain replays covered calibration, 180 ms sampling, boundary noise, wrong poses, narration timing, missing evidence, obsolete/duplicate callbacks, each coordination finger and one-count-only repetition completion. A temporary Simulator fixture used the actual activity, landmark overlay and bubble callback: it displayed 0.0/full with RETURN=false/SETS=0 while acknowledgment was deliberately withheld; after release, the return cue also published full before SETS became 1 (two full snapshots). The fixture required no camera, microphone or stored practice data and was removed afterward. Final Debug build passed. Physical tracking under actual lighting/tremor remains unverified.

## Fist repetitions and cleaner exercise screen (2 November 2026)

An actual-geometry replay reproduced zero repetitions: one occluded finger invalidated every fist sample, so the close timer never started. Grip metrics now require a visible wrist and at least two usable finger chains, retaining the 0.5 joint-confidence requirement and rejecting nonfinite/insufficient evidence. The palm reference for grip uses those visible chains instead of requiring the middle finger specifically. Coordination keeps its selected-joint requirements. These are camera-observed movement metrics, not verified grip force or full anatomical closure.

A fully earned endpoint is now distinct from a partial hold. During a brief hand occlusion, only the earned full/zero cue may retain its last accepted landmark anchor for up to 500 ms, with a fresh camera preview. That anchor is presentation-only and is never resubmitted as evidence. Partial holds still clear immediately, and prolonged loss, capture changes, pause or recalibration invalidate unfinished cycles. This allows the existing full-ring acknowledgment to complete without deleting a valid closing movement. A repetition still requires the observed close-and-open cycle; duplicate callbacks cannot add work.

The bubble shows the required two seconds from the start of the closing instruction, then counts down when the valid pose is held. Camera-presence badges, the large show-hand hint and the Start/Target bar were removed; permission/resource failures retain their recovery controls. Obsolete hint-latch state was removed with its UI.

Verification: actual geometry/activity replay passed a close/open cycle with an occluded finger and an earned completion surviving brief loss. A service-stub replay using the actual view model, geometry and engine counted two cycles as two repetitions and completed one set, including the delayed visible-ring callback. It also verified brief loss during completion, partial-hold cancellation, fewer than two usable finger chains, wrong-side rejection, prolonged loss and obsolete callbacks. A temporary Simulator fixture used the real exercise screen/view model/geometry/engine and automatic bubble acknowledgments with synthetic hand samples: the header visibly progressed from Ulangan 1/2 to 2/2 and Set selesai. It did not capture or save patient practice. All fixture source changes were removed before the final Debug build. Physical-camera acceptance remains pending.

## Continuous duration and stable camera layout (2 November 2026)

The exercise header now always shows session duration, current/total sets and current/total repetitions. The monotonic session clock continues through demonstrations, rest and tracking waits, and freezes during explicit pause/background/cleanup. It is separate from evidence-credited exercise duration in saved results.

The persistent camera defines stage layout; demonstration, celebration and rest are overlays. A reserved instruction region and hidden session status bar prevent phase changes from resizing the preview. Grip uses a viewport-sized enclosing ring instead of a changing hand bounding box. This supersedes the bounds-sized ring described above. Coordination keeps fingertip indicators.

Capture temporarily disables Center Stage, fixes the wide camera at its minimum ordinary zoom and disables supported stabilization; the previous Center Stage setting is restored on stop. Preview orientation and mirroring update only when needed, with implicit layer animations disabled. A bounded presentation-only landmark filter smooths visible points while original evidence, confidence and timestamps continue unchanged into scoring. Invalid joints, capture-generation changes and stale evidence reset the filter.

Verification: a synthetic replay reduced frame-to-frame landmark noise to 0.396 of raw input and verified generation/confidence reset behavior. The session-clock replay verified pause/resume and cleanup. A temporary Simulator fixture displayed duration, sets and repetitions throughout the actual session flow; pause froze the displayed duration and resume continued it. An initial rest viewport expansion was reproduced and corrected by removing layout participation from stage overlays; the measured viewport remained 1328 × 407 points in both active exercise and rest afterward. Fixture source and synthetic capture are removed before delivery. Actual iPad camera framing, lighting and tremor behavior remain physical-device checks.

## Achievement sharing (2 November 2026)

Earned badge details and the sequential award celebration expose a large localized Share badge action. Locked badges have no share action, and the shared router independently verifies the selected badge has an award before presenting the system sharing controller. Sharing does not acknowledge or advance the achievement queue. Completing or cancelling sharing returns to the previous sheet through the router.

A value-driven design system component renders an opaque, light appearance badge card at 2× scale in memory, with title, earned date and encouragement. Only this card and a localized caption are passed to the system; no patient history or camera data is attached. Rendering failure retains a text caption fallback. No file or Photos authorization is required. The user selects the destination and confirms delivery in the system UI.

Verification: the Simulator displayed the native share sheet and produced a visually inspected 1200-pixel-wide Indonesian badge image. The temporary sample route/export fixture did not save an award or send anything and was removed before the final build. Third-party destination delivery remains a device check.

## Sequential extension timer detection (3 November 2026)

An actual geometry/activity replay reproduced a stationary zero timer when a bent distal joint straightened while the middle joint was already straight. Extension previously measured only the middle-joint angle. It now averages middle and distal extension angles for the selected finger, matching the required visible fingertip. Palm validity uses that finger's own base; an unrelated middle-finger MCP landmark no longer blocks another finger. Existing confidence, freshness, calibration separation, hold duration and visible-completion acknowledgment requirements remain intact.

The original replay changed from holdElapsed 0.0 to 2.0/full completion. An expanded replay covered all four calibration pairs and one full sequential repetition, wrong/unchanged finger rejection, unrelated middle-joint occlusion and missing selected joints. The temporary replay was removed after validation. Physical camera detection remains a device check.

## Tracking display continuity (3 November 2026)

A synthetic replay reproduced a 0.345 normalized horizontal jump in the displayed hand from one spurious detection frame. The display filter now requires a second nearby observation before accepting a displacement above 0.18 aspect-correct image heights. Genuine sustained movement is followed after confirmation; raw evidence and confidence remain unchanged for the activity. Long gaps and capture changes still reset the filter.

A brief missing/invalid observation no longer immediately destroys the smoothing history. The last accepted overlay may remain for 150 ms while tracking is unavailable; its partial hold timer and progress are hidden, and evidence credit suspends immediately. Earned completion cues retain their existing separate 500 ms acknowledgment policy. This supersedes the earlier immediate drawing-filter reset on every unusable sample.

The capture inference gate allows 1 ms of timestamp rounding tolerance. A 30-FPS replay previously accepted only 21 observations in two seconds due to every-third-frame slips; it now accepts the intended 30 with every-second-frame spacing. Latest-value delivery is bounded at 60 ms rather than 70 ms so a normal 15-Hz result is not unnecessarily skipped. Late camera frames remain discarded instead of queued.

Verification: actual-filter replay passes isolated-spike suppression/recovery, sustained movement, long-gap and generation resets, and raw-evidence preservation. The cadence replay passes 30 updates per two seconds. Simulator build passes. Temporary scripts are removed. Preview FPS, thermal load, real occlusion/tremor and camera smoothness still require the baseline physical-iPad run; no physical-device acceptance is inferred.

## Smaller tracking spikes and indicator pulsing (3 November 2026)

A second actual-filter replay exposed a smaller 0.08 normalized single-frame spike below the earlier large-jump threshold: the display still moved 0.0735. A three-sample coordinate median now precedes adaptive smoothing; speed adaptation uses the filtered trajectory rather than raw detector noise. The same replay now reports zero displacement for that isolated spike. This adds roughly one observation of presentation latency; scoring remains on fresh, original evidence.

Low-confidence joints may retain their last drawn position and presentation confidence for at most 150 ms. This is a visual bridge only, never passed to the engine. Unrecovered or invalid joints are hidden; reacquisition within the grace blends from the previous position. This updates the earlier statement about preserving confidence in displayed evidence: original scoring confidence remains unchanged, while the drawing copy can briefly retain a prior valid confidence. Long gaps, new capture generations, side or image-size changes still reset history.

Indicator selection/size now uses presentation availability separately from hold-clock availability. The currently selected ring no longer shrinks and grows when a short miss suspends hold timing. Partial progress still clears and no missing interval earns credit. The full-ring acknowledgment continues to require the existing active timer/completion gate.

Verification: actual-filter replay passes moderate spike rejection, short confidence loss and expiry, sustained movement, long-gap reset and unchanged raw evidence. Simulator build passes. Temporary diagnostics are removed. Physical camera verification remains pending; these synthetic checks cannot establish that every real detector glitch is resolved.

## Combined garden activities (3 November 2026)

Work continues on `codex/garden-exercises`, carrying forward the uncommitted timer-placement and tracking improvements. The five existing finger movements now drive a shared garden theme: fist gathers/releases light, hook fist gathers/releases rain, opposition lifts/plants seeds, spreading opens/closes petals, and sequential extension lights four stepping stones. The original instruction, example video, calibration, holds, full-ring acknowledgment, set/repetition rules and session engine remain authoritative. Art cannot send progression events.

A fixed side rail keeps the existing example above the live game, outside the hand preview. The camera remains mounted with the same viewport across phases. Artwork uses supplied pose, accepted hold progress, selected finger and completed substep counts. It does not run a game timer. Pause or missing tracking disables animation and hides earned-hold progress; no detection gap earns rewards. Validated returning movements update the seed/path counters; calibration fingers never count. Optional step feedback reuses bundled target-reached audio through the existing audio owner, respecting calm mode and celebration-sound preferences. Set completion retains its existing sound/celebration and displays a flower.

Home, finger Home and Reports show five garden beds. Each saved completed set adds one flower in its movement's bed. Saved partial repetitions can show a seedling without adding a flower. Garden totals derive from deduplicated finalized local history; no schema migration, new storage or camera data is introduced. Saved-for-later checkpoints and empty work do not contribute. Deleting a historical report removes its contribution. Existing earned badges provide up to four tappable garden decorations through the shared router. Report details identify the session's new flowers.

Garden activities default on and can be turned off in presentation settings to compare with the simpler session. Calm mode and Reduce Motion suppress transitions; illustrations remain responsive without decorative looping animations. All new user copy is available in English and Indonesian. No speed targets, penalties, withering, bonus repetitions or inferred grip-force claims were added.

Verification: a temporary actual-domain history replay passed cross-session accumulation, duplicate/checkpoint/empty-work rejection and seedling behavior. Temporary Simulator fixtures exercised the actual session screen/engine with synthetic hand samples, showed seed and stepping-stone progression alongside the unobscured hand area, and inspected all five artwork themes. They did not request capture or store practice. Fixtures are removed before production build. Physical-iPad comfort, tracking, audio coexistence and performance checks remain pending.


## Garden inside the camera and recovery (3 November 2026)

This replaces the separate side rail described above. A small corner demonstration remains over the persistent camera. Transparent light, a revealing leaf/flower, a selected-finger seed, translucent petals and a selected-finger firefly respond to the five existing movements. One object is active at a time; accepted returns send objects to a fixed planter at the bottom edge. The hold countdown remains outside the hand. Pose feedback can respond before acceptance, but collection requires the original accepted target and return. Calibration and missing evidence never produce rewards.

Brief tracking loss parks the object and suspends scoring immediately. A delayed, stable hint avoids flickering messages: position the hand, use the selected side, show the required fingers, or leave only one hand visible. Sustained loss opens the shared pause sheet. Stable recovery never resumes automatically; the patient explicitly continues. Camera startup receives a longer grace period than an interrupted running camera. Permission failures offer Settings and Check again; camera/audio failures offer retry. Calibration with no accepted hold offers retry without relaxing acceptance thresholds.

Save failures retain pending results and block unsafe continuation until retry succeeds, even if a camera error occurs simultaneously. Sharing cancellation returns normally; actual sharing errors offer retry. Session language stays fixed for text/narration, with English on-device voice commands independently of narration language. Backgrounding stops resources and requires explicit continuation after recovery.

Verification: production-helper replays passed recovery debounce, stable reacquisition, timeout and camera-layout bounds. A temporary Simulator fixture exercised the actual view model and engine: calibration/partial holds produced no deposits, accepted return produced one, duplicate updates produced none, recalibration preserved collected objects, preview detachment prevented recovery, Settings return restarted the clock, storage and camera errors could not mask each other, and failed finalization retained retryable results. Native screenshots confirmed seed/leaf placement, detached hold timer, waiting artwork, pause sheet and explicit command resume. Synthetic fixtures were removed; no patient capture or practice data was saved. Physical iPad camera tracking, microphone recognition, comfort and performance remain pending.


## Butterfly shelter and pinched seeds (4 November 2026)

Hook fist now folds a leaf as the fingers bend. After an accepted target hold, the required return opens the shelter to reveal a butterfly; accepted return triggers one bounded flight to the garden. An unaccepted bend may move the leaf but cannot reveal/collect a butterfly. Opposition uses one small seed at the screen-space midpoint of the thumb tip and only the active fingertip, with two light tethers identifying that pair. Contact compresses the seed; accepted target secures it, and accepted return plants it in the bottom-edge pot. Sequence advancement and scoring remain owned by the original activity. Pot counters for these styles represent accepted substeps of the current exercise rather than mixing seed/butterfly counts with other movements.

Tracking loss keeps the existing parked artwork and removes uncertain tethers. Pause/background cancel decorative flight; Reduce Motion/calm mode suppress flight. The hold timer stays outside the hand and only the small seed occupies the active contact area. Primary exercise instructions remain intact, with short bilingual supporting cues. (The Twemoji artwork described here was replaced on 4 November 2026 by original kampung artwork; see below.)

Verification: an actual-geometry activity replay passed hook target/return gating, absent-evidence noncredit, obsolete/full-ring acknowledgment and all four opposition finger cycles. A layout replay checks mirrored thumb/selected-tip midpoints and butterfly viewport bounds at two landscape sizes. A temporary Simulator artwork fixture confirmed the actual vector assets, folded/open leaf, revealed butterfly, single seed/tethers and pot rendering without camera/microphone or saved exercise data. Fixture startup was restored and the final production Debug Simulator build passed. Physical-iPad tracking, fingertip occlusion and visual comfort remain pending.

## Kampung finger games (4 November 2026)

The five finger movements now drive an Indonesian village theme with one natural mapping each, replacing light, leaf, seed, petals and firefly:

| Movement | Game | Moving out | Returning |
| --- | --- | --- | --- |
| Full fist | Squeeze a jeruk | The orange flattens; juice drops appear | Juice flies to a glass (five oranges fill one glass) |
| Hook fist | Draw water from the sumur | The bucket rises from the water | Water flies to a pot; the sprout grows |
| Opposition | String a melati garland | A jasmine flower glows at the pinch | The flower joins the garland (12 per garland) |
| Spreading | Open a kembang sepatu | The bud opens into a hibiscus; a butterfly lands when the target is secured | The butterfly flies to the garden |
| Sequential extension | Ring bamboo chimes | The named finger's tube glows and leans | That tube rings with its own pentatonic note; a full sequence plays a short tune |

Cognitive-load rules retained: one active object, one fixed mapping per movement, short bilingual supporting cues, no timers, scores or failure states, and no reading during movement. Solid artwork sits beside the hand (only the small melati is near the pinch, offset upward), so the patient's own fingers stay visible. The engine remains the only source of acceptance; artwork reads pose, secured state and accepted deposit identity. Chime sounds follow the celebration-sound preference and calm mode. Reduce Motion and calm mode suppress flights and swings.

Verification status: source changes only. Simulator build, visual placement against live hand tracking and physical iPad comfort/audio checks are pending.
