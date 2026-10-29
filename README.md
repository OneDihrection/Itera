<!-- README.md — Created by Amelia Putri Aftiana on 29/10/2026. -->

# Itera: latihan jari

Native iPad app for the five requested finger exercises: full fist and release, hook fist, thumb-to-finger opposition, finger spreading, and sequential finger extension. This branch implements the user's finger-only scope in place of the original arm/reach/cup scope in SYSTEM_DESIGN.md, retaining the single target, router, domain ownership, local storage, and manual verification policy.

## Run

```sh
xcodegen generate
open Itera.xcodeproj
```

Select the Itera scheme and an iPad Simulator or connected iPad, then Run. For device signing, set your bundle identifier and development team in project.yml, then regenerate. Persistent configuration belongs in project.yml.

Validated tooling: Xcode 27.1 (27A9275), XcodeGen 2.45.4. Minimum deployment is iPadOS 17.0, iPad only, landscape in either direction. If command-line tools point at CommandLineTools, choose Xcode under Xcode Settings → Locations, or set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for build commands.

Home and Reports use native system tabs, with separate paths owned by the shared NavigationRouter. Native navigation bars, settings forms, and sheets provide familiar controls. Home and the plan list use image cards and shorter Indonesian copy; detailed caregiver and measurement explanations remain available through disclosure controls. Colors adapt to system light/dark appearance; accessibility text sizes stack the home/plan columns vertically. Plus Jakarta Sans, large touch targets, and the original session/calibration rules are retained.

Indonesian and English are in String Catalogs. Select Bahasa Indonesia as the app language in iPad Settings for Indonesian text, narration, and voice commands. No custom language picker overrides the OS. The session freezes its selected narration/recognition language.

## Flow and controls

Beranda → rencana latihan → camera permission → comfortable-range calibration for each movement → full demonstration → countdown → sets and automatic rests → feeling check → report. Laporan is the second main destination. A caregiver selects the anatomical hand under Atur latihan, 1–5 sets, 1–20 repetitions, and 5–120 seconds of rest. These defaults are editable demonstration settings, not a prescribed stroke rehabilitation dose.

Controls are at least 64 points tall, with Plus Jakarta Sans hierarchy and large exercise instructions. Physical readability at 1–2 metres is still unverified. Camera hand-detail quality also depends on distance, light, occlusion, and hand size in the image; move closer if fingers cannot be identified reliably.

Voice control is optional and requires microphone/speech authorization plus available on-device recognition. Indonesian commands: “jeda”, “lanjut”, “akhiri”, “ulangi”. English: “pause”, “continue”/“resume”, “stop”, “repeat”; “lanjutkan” is also accepted in Indonesian. Exact pause/stop partials act promptly. Resume/repeat require a final result or a briefly stable exact phrase. Accepted requests are processed once and stale callbacks are ignored. Recognition remains active during narration; failure pauses the session and requests acknowledgment of touch controls. Reliable interruption and self-trigger rejection still require physical-device validation.

Pause preserves completed work and offers resume, save for later, caregiver skip, or end. Skipped movements receive no completion credit. Continuing later checks movement again and preserves completed repetitions/sets; calibration is never persisted. Backgrounding stops camera/listening and pauses progress. Resume is explicit.

## Camera estimates

Vision detects one unambiguously identified hand. Its chirality must match the selected anatomical side. Unmirrored normalized coordinates are scored; preview and overlay share aspect-fit geometry and mirror only for presentation. Landmarks use wrist index 0 and fingertip indices 1–5.

Calibration holds a comfortable starting pose for two stable seconds, then a distinct comfortable target for two seconds. Opposition and extension calibrate all four named fingers separately. Practice requires start → target → start with 250 ms zone dwell. A full four-finger sequence is one repetition for sequential activities. Low confidence, multiple hands, stale frames, nonfinite measurements, or unavailable tracking never create credit. Capture discontinuity/rotation requires recalibration. Inference runs on a serial capture queue at up to 15 Hz with late-frame dropping; the preview runs separately.

The indices use projected finger bend, normalized fingertip separation, or thumb-to-tip distance. They are not grip force, clinical joint angles, verified fingertip contact, or proof of recovery. Reports compare the best stable movement with that session's calibration range; changes of 5% or less are not promoted as increases. Perspective and occlusion can affect these estimates. Clinical suitability, thresholds, and accuracy need therapist review and physical validation. Exercise amount should follow the patient's therapist's directions. The post-session check records perceived difficulty (difficult / just right / easy); historical comfort, tiredness, and pain entries retain their original labels.

## Local data

Repository actors share atomic JSON file mechanics in Shared/Storage. Application Support holds a versioned plan, active-session checkpoint, and one summary file per session ID. Unreadable/unsupported records surface an error and are not replaced with empty defaults. Starting a new session preserves a previously pending session as interrupted. Unexpected termination finalizes the checkpoint as interrupted on launch. Finalization cannot be resurrected by a late checkpoint.

No video, microphone recording, landmarks, or detailed frame measurements are saved. Summary data includes the routine snapshot, observed repetitions/sets/time, skipped/incomplete states, relative movement change, and feeling. Deleting a report removes only that summary. There is no app-managed cloud sync; these Application Support files remain eligible for the installation's normal OS backup policy.

## Assets and references

The current hand demonstrations use the user's supplied `rigged_hand.blend`. Its original bytes are preserved in ArtSource/Reference/rigged_hand.blend and the Downloads original is untouched. The adapted scene is ArtSource/RiggedFingerDemonstrations.blend. The original authored mesh, weights, and rig constraints are retained; new guidance animation uses its open/fist poses and fitted thumb-to-finger poses. The controller scale curls the middle/end joints for hook fist while the main knuckles stay extended. The previous procedural scene is retained as earlier source work, but its clips are replaced in the app.

Tools/create_rigged_hand_demonstrations.py builds the adapted scene; Tools/render_rigged_hand_demonstrations.py renders the five silent H.264 MOV files and six transparent catalog images. The scene was inspected through Blender MCP and rendered with Blender 5.1.2. Paths resolve from the scripts' location. The videos are 640 × 640 at 24 fps. Three simple movements last 4 seconds each; opposition and extension last 16 seconds each. Runtime playback retains its 4-second subclip/half-cycle contract, so written and spoken cues select the corresponding motion. Reduce Motion uses held poses. Left-hand guidance mirrors the right-hand source. A local Vision check classified the unmirrored rendered open hand as right; physical anatomical-side checks are still pending.

Source/provenance details for the user-provided mesh are recorded in ArtSource/Reference/README.md. No new license or authorship is asserted for the supplied Blender binary.
Plus Jakarta Sans regular/bold: [Tokotype](https://github.com/tokotype/PlusJakartaSans), distributed under the bundled SIL Open Font License. App typography uses only the bundled Plus Jakarta Sans faces. The optional low-volume background WAV is an original synthesized tone, described by Tools/generate_ambient.py; narration lowers it and pausing silences it. No third-party audio or video is copied.

Movement references, used for movement descriptions rather than prescribing treatment:

- [NHS tendon-gliding instructions](https://www.nth.nhs.uk/resources/hand-therapy-tendon-gliding-exercises/): hook versus full fist geometry.
- [East Kent tendon-glide leaflet](https://leaflets.ekhuft.nhs.uk/tendon-glide-exercises/): spread and return.
- [National Clinical Guideline for Stroke](https://www.strokeguideline.org/chapter/motor-recovery-and-physical-effects-of-stroke/): individual goals and suitability of rehabilitation.
- [User-supplied YouTube reference](https://www.youtube.com/watch?v=2CuujPY3DAw): the page was accessible but video frames/transcript were not exposed; its detailed movement was not independently verified.
- [Hand appearance reference](https://blenderartists.org/t/realistic-3d-hand/652233): visual reference only, no mesh downloaded or copied.

## Verification

On 29 October 2026, Xcode 27.1 built the single Itera target successfully for an iPad Pro 13-inch (M5) Simulator running iPadOS 26.4.1, with signing disabled and deployment target 17.0. Regeneration and git whitespace checks passed. AVFoundation read the exported clip durations as 4/4/16/4/16 seconds. Bundled videos, fonts, catalogs, and audio were inspected in the app bundle.

Simulator walkthrough covered Indonesian home/plan, permission flow, unavailable-camera recovery, pause/end, the mandatory feeling check, and a persisted report with zero repetitions rather than fabricated credit. The bundled hand frame was visible in the session mini window. A pending-permission setup race discovered during this walkthrough was fixed.

Physical M1-iPad acceptance is **pending**: both landscape orientations and anatomical sides; overlay alignment; all five comfortable-range calibrations; occlusion/multiple-hand/stale evidence; complete sets and automatic transitions; normal pause versus discontinuity; continue-later recalibration; on-device voice availability and interruption during every cue; offline voice resources; Reduce Motion; 1–2 metre readability and tracking; two-minute body/hand tracking performance and thermal behavior; corrupt/unsupported/failed storage; and full lifecycle cleanup. Simulator builds do not establish camera accuracy, clinical validity, audio reliability, or physical-device acceptance.

### Home/list redesign verification

The redesign follows the supplied workout-screen structure while retaining Itera's data and session rules. Apple references: [Writing](https://developer.apple.com/design/human-interface-guidelines/writing), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [Navigation and search](https://developer.apple.com/design/human-interface-guidelines/navigation-and-search). The optional Mobbin search was unavailable because it required a paid plan; no Mobbin reference is claimed.

The revised Simulator build passed on 29 October 2026. Home/plan rendering, native back navigation, settings-sheet opening, changing/restoring the saved set amount, and opening/toggling the example preview were walked through. Export durations and 24 fps were read back with AVFoundation. A preview loop issue was identified by sampling the app: pausing at an endpoint retriggered the time observer and repeatedly queued seeks. The renderer now gates seeks, waits for completion, ignores obsolete completions, and holds non-looping endpoints once. That fix builds successfully.

After the Mac was unlocked, playback was verified advancing at rate 1 and repeating the complete 16-second sequence without the seek storm. The preview changed hand poses and the interface remained responsive. Preview Pause now holds the current pose, and Play resumes it rather than jumping back to the first frame. The final square preview viewport was checked with the full hand visible. Dark appearance and enlarged accessibility text were inspected; the home/plan stack into one column, and the main action remained operable. Illustration height was capped to keep enlarged text from producing an oversized decorative image. Temporary playback diagnostics were removed after checking media time/rate. Physical iPad acceptance remains pending as above.

### Session layout and tracking refinement — 29 October 2026

Instruction/demo uses a large example beside short guidance. Calibration and exercise retain one mounted camera preview, with a corner example, wrist hold ring, indexed joints, and live text. Active practice also shows a start-to-target movement gauge based on the observed normalized metric. The countdown covers the whole screen with an animated ring and number; tapping it opens pause controls, including End. Voice commands and the accessible End action remain available. Set completion has an original quiet chime and a short bounded confetti burst; Reduce Motion retains a static success symbol. All clips share a sage studio backdrop matched by the media container. Primary green, secondary sage, and tertiary peach are shared palette roles.

Finger calibration keeps its two-second stable hold and distinct-target requirement, with stability tolerance increased from 0.08 to 0.10 metric units. Practice accepts 80% of the captured range (previously 85%), a 25% return zone (previously 20%), and 250 ms dwell (previously 300 ms). Required geometry still needs confidence 0.5; unrelated occluded joints no longer block an exercise. Hook-fist MCP acceptance is 125° instead of 135° in the projected camera geometry. Missing evidence clears holds and earns no time; up to 500 ms preserves an already accepted outward leg, then requires return to start. Capture failures/discontinuities still require explicit recovery and fresh calibration. These are technical tolerances awaiting physical and therapist review, not validated clinical thresholds.

Verification: the revised Simulator build passed. A temporary, non-persistent layout harness displayed the instruction, calibration, active, countdown, set-success, and reflection compositions; it was removed before the final build. The feeling choice remains unsubmitted until Next; selecting Pas enabled Next. Countdown accessibility exposed only the timer and its End action, and tapping it opened all pause/recovery controls. The Simulator cannot supply valid rehabilitation tracking evidence here, so these checks establish layout and control behavior only. Real camera, voice overlap, cue audibility, animation comfort, new tolerances, and performance on the baseline physical iPad remain pending. No synthetic repetitions or reports were saved.

### Timer stall fix — 29 October 2026

Missing-hand callbacks cleared both evidence holds and the stage clock's previous tick. With a missing hand arriving between timer ticks, demo/countdown/rest could never accumulate elapsed time even while preview frames remained fresh. Evidence resets now leave the stage clock alone. Explicit pause/resume, unavailable preview frames, and recalibration reset that clock separately so recovery cannot credit missing intervals. Completed narration IDs are cleared, preventing a later camera gap from treating finished speech as pending. Camera retry also ensures the session timer exists after initial permission denial.

The main exercise header now offers Pause; End remains in its pause menu. The video example shows elapsed example time, including playback during narration. Real camera waits show a localized waiting message and pause the example as well as stage timing. Active practice time and repetition evidence rules are unchanged.

Verification: a throwaway replay compiled the actual domain activity/engine and reproduced all three frozen timed stages before the fix. The same replay passed after the fix, including missing-hand callbacks, short evidence suspension, unavailable-camera freezes, recovery without time credit, explicit pause/resume, and example time during narration. No automated test target was added. A temporary non-persistent Simulator harness confirmed the visible example counter (00:05), automatic advancement into practice, and a Pause-only header. That harness was removed before the normal build; no sample reports or repetitions were stored. Physical camera/audio interruption checks remain pending.

### Achievements, streaks, and feedback — 29 October 2026

Reports now include a weekly repetition bar chart and active-minute line/area chart, previous/next-week navigation, current/best daily streaks, and 50 small milestones across repetitions, sets, practice days, streak lengths, sessions, and five movements. Home also displays the current streak. A day/session qualifies after at least one accepted repetition in a finalized summary; stopped/interrupted sessions retain their recorded work. Duplicate session IDs and multiple sessions on the same local-calendar day cannot inflate streaks. A streak remains current through the day after the latest practice and resets after a missed day. Calendar arithmetic handles daylight-saving boundaries. These rewards recognize participation, not recovery, strength, or a prescription to increase exercise.

History owns achievement aggregation and its own protocol-backed ledger, consuming Therapy's narrow history-reading contract. `practice-achievements.json` in Application Support stores versioned earned IDs/dates and popup acknowledgments with atomic writes on its repository actor. Popups batch newly earned badges after a session is saved and the report opens; the shared router owns presentation. Acknowledgment is persisted so refreshing/relaunching does not repeat seen rewards. Deleting a session report recomputes charts/current streaks but preserves earned badges; deleting a report does not delete this separate ledger. Unreadable/unsupported ledgers surface an error and are not silently replaced. No camera streams or landmarks are stored.

An original bundled 60 ms button-click WAV plays on activation through the existing sole audio-session owner, using a separate cached player so clicks do not cancel guidance speech. Design system controls receive a feedback action through the environment; they do not reference feature models or services. Touch, keyboard, and accessibility button activation use the same action path; disabled controls do not trigger it. Outside sessions, UI audio uses ambient mixing. During sessions, the existing audio category remains in control. Physical audibility, comfort, silent-mode behavior, and speech/recognition overlap still require iPad verification.

Verification: Simulator build passed. Temporary diagnostic execution of actual aggregation/repository code checked duplicate/same-day sessions, current/best streaks, yesterday grace, missed-day reset, atomic award deduplication, acknowledgment across reload, retained awards after deleted history, and unsupported-schema rejection without overwrite. A non-persistent layout fixture checked populated charts, batched popup acknowledgment, badge detail, week navigation, dark appearance, and accessibility text size. The fixture was removed before the normal build; no sample reports or awards were saved. Larger-text layouts stack charts and streak content. Original Light appearance and text size were restored. Chart API reference: [Apple Charts](https://developer.apple.com/documentation/Charts/Chart).

### Voice parity and restful motion — 29 October 2026

The Pause control is now a 92-point icon-only design-system button with a localized accessibility label. Touch and recognized speech both call the same session command handler. “Pause”/“jeda” sets the engine's paused state and opens the existing pause panel; “continue”/“resume”/“lanjut”/“lanjutkan” explicitly resumes the same stage and closes it. The resume guard applies equally to voice and touch, including failed-save warnings, saving, voice fallback acknowledgment, and ended sessions. Ordinary pause keeps recognition available; the panel displays a listening hint when voice mode is on.

Command phrases now live in String Catalogs and bias on-device recognition through contextualStrings. Exact pause/stop partial results can interrupt guidance promptly. Resume/repeat partials must remain exact for 350 ms (or become final); an expanded non-command transcript cancels the candidate. Each consumed command rotates request identity so later revisions cannot repeat it. Disabling voice cancels pending commands. A stop that synchronously releases audio cannot restart the microphone from its old callback; failed voice startup releases partial resources. This does not establish microphone accuracy or echo rejection: ambient conversation, dysarthric speech, narration overlap, repeated commands, interruptions, and selected-language voice resources still require physical iPad acceptance. No audio is sent to a server or retained.

Rest uses a lightweight decorative garden of slow waves and floating leaves behind the existing timer. Its 24 Hz timeline stops while paused, waiting for camera frames, backgrounded, or under Reduce Motion; Reduce Motion shows a static garden. The backdrop is noninteractive, hidden from accessibility, and owns no exercise timing or counts.

Verification: the Simulator build and command-phrase checks passed. A temporary headless replay compiled the actual view model and domain logic with substitute platform services and drove real Combine audio-command events. Active, rest, demonstration, and countdown retained their stages across voice/touch pause/resume; blocked saves and post-stop resume were rejected. Temporary replay/layout scaffolding was removed before the normal build and saved no exercise data. Initial visual verification was blocked by the locked Mac. The follow-up screen checks below completed after unlocking; physical voice reliability remains pending.

Follow-up screen verification, 29 October 2026: iPad Pro 13-inch (M5) Simulator, iPadOS 26.4.1, app version 1.0 Debug build. An isolated rest preview bypassed unavailable Simulator camera events and persistence. Replaying recognized “pause” through the actual audio-event subscriber opened the pause panel; replaying “continue” closed it and restored the same rest stage. The 92-point icon-only Pause and touch Resume produced the same visible transitions. Normal-motion rest captures differed at 371 sampled pixels; Reduce Motion captures differed at zero sampled pixels, confirming the decorative animation and static fallback. Original Reduce Motion-off setting was restored. All temporary replay controls and camera/persistence bypasses were removed before the normal build. Microphone transcription accuracy, echo rejection, voice availability, and physical iPad performance remain pending; this was a command-routing/UI check, not an acoustic acceptance test.

## Arm and reaching sessions

The arm-raise, elbow-bend, and directional-reaching workflow from main remains available from Home alongside finger practice. It retains its separate routine and session repositories. See [session verification](SESSION_VERIFICATION.md) for checks and outstanding physical-device acceptance.
