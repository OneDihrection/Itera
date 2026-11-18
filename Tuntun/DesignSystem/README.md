# Design system

Tuntun UI component types use the `TM` prefix, including feature views, UIKit view adapters, and view styles.

This folder owns reusable UI controls and styling for Tuntun. Follow the repository [agent instructions](../../AGENTS.md) and [system design](../../SYSTEM_DESIGN.md).

Every agent doing UI work must inspect `Tuntun/DesignSystem` and read its README first. Use existing reusable controls and styling from that folder. If no suitable component exists, create a reusable one there before using it. Extend compatible components instead of duplicating controls or styling in feature folders.

Screens may use native SwiftUI layout directly; navigation must use the feature's router. Feature views own screen composition; therapy-specific compositions may remain in their feature, using design system controls and styling. Add components only as needed; do not build a speculative library or wrap every SwiftUI primitive.

Design system components accept values, bindings, content, and actions as needed. They must not depend on feature view models, repositories, or exercise logic.

Typography owns the bundled Plus Jakarta Sans faces and semantic scaling. Components/TherapyControls.swift owns semantic light/dark surfaces, pastel illustration colors, large action buttons, cards, status labels, metrics, value controls, and error presentation. Components/TherapyArtwork.swift owns illustration panels and accessible image rows; it accepts asset names, values, and actions without exercise logic. Native tabs are owned by App/RootView.swift and navigation stacks by each feature's stack-owning screen, and settings use native Form, Picker, Toggle, and DisclosureGroup layouts. Extend these controls when compatible instead of adding feature-local copies. The existing recursive source entry in project.yml includes new components automatically.

## Navigation, typography, and code conventions

Each feature owns its navigation through its router. The screen that owns a stack declares its `NavigationStack(path:)`, `.navigationDestination`, sheets and covers from state on its screen view model, and that view model wires the feature's `…Router` hooks (closures such as `push`) to that state. Every other page and view model on that stack receives the router through its initializer as a `…RouterProtocol`, and destinations are built only by the feature's builder. Never read a router from the environment; cross-tab navigation goes through `TabRouterProtocol`. Native SwiftUI layout remains allowed.

Use .typography(...) or inherit the root body style for app-authored text. Font names and direct font styling belong only in DesignSystem/Typography.

Keep body focused on composition. Prefer named private computed view properties, using @ViewBuilder for conditional or multiple-view sections, or dedicated subviews for meaningful sections with inputs, bindings, state, reuse, or substantial complexity. Reusable controls belong in DesignSystem; avoid splitting trivial expressions mechanically.

Every newly authored file must have a format-appropriate header with its filename, actual author, and creation date. Use an explicitly supplied author first, otherwise effective git config user.name; ask if neither exists. Never hard-code a team member or use the AI's name. Preserve existing creation authorship. Swift uses Xcode-style // Created by headers; YAML uses comments and Markdown uses HTML comments. Preserve copied binaries and third-party licenses unchanged and document their source separately; never corrupt formats without comment support.

Prefer generous spacing and readable multiline declarations, calls, expressions, and conditions. Use /// Markdown API documentation when helpful and // MARK: - sections in longer files. Comment non-obvious purpose, constraints, and lifecycle behavior rather than restating syntax.

Components/TherapyFeedback.swift owns value-driven progress rings, a timer-only countdown with accessible pause/end actions, bounded success confetti, and large feeling choices. Primary green, secondary sage, and tertiary peach roles are defined in TherapyPalette; mediaBackground matches the fixed rendered hand studio. No component owns session timing, tracking, or persistence.

Components/TherapyButtonFeedback.swift supplies a primitive button style whose activation calls an injected environment feedback action, then the original action. The composition root injects the sole audio owner's click method. Controls retain native disabled/activation behavior.

TMTherapyIconButton in Components/TherapyControls.swift provides a large icon action with an explicit localized accessibility label.

## Session guidance

`TMMeasuredInstructionText` adapts VisionPoc’s measured, scrollable instruction reader. It accepts rendered text, a request identity, scaled font size, accessibility settings, and a reading-status callback. It owns measurement and presentation pacing only; the session engine decides when to advance. Typography resolves UIKit fonts alongside SwiftUI fonts in Typography.

## Full-screen session presentation

`TMSessionStageSurface` provides the reference experience’s full-screen surface, 48-point inset, 24-point section spacing, and continuous 36-point border. It accepts content and controls without knowing about session state. `TMSessionCelebration` provides a cancellable three-second visual celebration and pauses its animation timeline afterward; the caller handles Reduce Motion. Its particle layout was adapted from VisionPoc’s `TherapyClosingSection.swift`.

`TMTherapyGuideBubble` displays supplied hold progress without owning tracking or timers. Button activation uses a short press response without changing the original action or accessibility activation.

`TMTherapyGuideBubble` accepts an optional diameter and outline-only styling for enclosing indicators. Its explicit `showsTimer` input enables the progress arc. The full arc marks completion.

`TMTherapyGuideBubble` accepts a completion identity and presentation callback. It reports a completed, visible cue after a cancellable 250 ms settle period, only while active in the foreground. This is presentation acknowledgment, not exercise-time credit. The activity retains its full/zero snapshot until the session receives that matching acknowledgment. Final progress renders without animation lag; partial ring updates interpolate independently of the acceptance clock.

`TMTherapyGuideBubble` accepts a `tint` (default `guidanceBlue`; finger guidance passes `guidanceOrange`) and `drawsBackground: false`, which draws only the progress arc for a caller that draws the circle itself.

`TMTherapyPopBurst` (Components/TherapyPopBurst.swift) plays a half-second "bubble pops" burst each time its integer `trigger` changes: a ring in the tint swells slightly and fades while eight droplets fly past it and shrink. Reduce Motion keeps only a brief fading ring. `TMTherapyGuideBubble(popsOnCompletion: true)` and `TMTherapyMergingGuide(popsOnCompletion: true)` fire it when a completed hold becomes visible, the same signal that acknowledges the hold.

`TMTherapyMergingGuide` (Components/TherapyMergingGuide.swift, shader `mergingGuide` in Components/MergingGuide.metal) is the one indicator every exercise uses. It draws two guide circles that flow into one as a supplied `merge` value goes from 0 to 1: a smooth-union shape forms a rounded bridge and a single circle remains, so only one indicator shows. With `anchor: .midpoint` (default, thumb opposition) the centres slide to their midpoint and the merged circle is about 12% larger; with `.second` the second circle stays fixed and the first (`firstDiameter`, which may differ) slides in and takes its size, so a target's drawn outline stays its acceptance boundary; with `.fixed` neither circle moves or resizes, `merge` only widens the bridge and the arc sits on the second circle. The bridge narrows as the centres meet, so coincident circles (merged or single) keep exactly their size and match the arc, and the shader layer is padded for the bridge so nothing is clipped square. `mergeAnimation` (default a 0.35 s spring with slight bounce) lets a caller choose a calmer ease. A white outline over an outer dark underlay keeps contrast on video, and the soft fill and the progress arc use the tint (orange by default); `active: false` draws a quiet half-strength outline with no fill, and `filled: false` keeps an active outline without the fill, for a circle drawn around the whole hand. `firstSymbol` and `secondSymbol` put a white glyph on a dark disc at each centre (the first fades as they merge), and `init(center:diameter:...)` draws one circle in the same look for hold rings, lone markers and the whole-hand circle (it also takes the completion identity, `popsOnCompletion` and `filled`). The arc is a `TMTherapyGuideBubble` laid on the shader outline, so completion acknowledgment is unchanged. The caller computes `merge` from its own geometry; changes ease with a 0.35 s spring, applied at once under Reduce Motion. It owns no tracking or timing.

`TMTherapyMetric` supports compact label spacing for horizontal session headers, retaining its large numeric value and combined accessibility label.


## Monochrome pages

The home, exercise start, session pages and progress page use a monochrome look: a white `canvas`, black `heroCard` surfaces with `onHero` text, grey `panel` fills, thin `outline` borders and dark `action` pills. `success`, `setDone`/`setDoneFill`, `restRing`/`restTrack` and `challengeFill`/`challengeInk` cover the few coloured states. All are light/dark adaptive tokens in `TherapyPalette`, mapped to system semantic colors (`label`, `systemBackground`, `secondarySystemBackground`, `separator`, `systemGray5`, `systemGreen`, `systemBlue`) wherever one fits.

Existing controls gained compatible options instead of copies: `TMTherapyButton(pill:)` draws the dark pill (grey when `secondary`), `TMTherapyIconButton(circle:)` draws the black back/close circle with a 64-point touch target, `TMTherapyCard(outlined:padding:)` draws a bordered white card, and `TMTherapyProgressRing(tint:track:lineCap:)` recolours the ring. `TMTherapyTextButton` is a quiet text action for secondary choices beneath primary buttons.

Components/TherapyPageLayout.swift owns `TMTherapyPageHeader` (centered title with a leading close circle, for full-screen session pages that have no navigation bar) and `TMTherapyMediaPanel`.

Components/TherapySessionStatus.swift owns `TMTherapyCompletionMark` and `TMTherapyFeedbackPill`. They display supplied values only; set progress and timing stay in the session.

Components/TherapyProgressSummary.swift owns `TMTherapyWeekSummary`, `TMTherapyProgressSessionCard` and `TMTherapyWeeklyRepetitionChart`. Callers pass formatted values.

### Human Interface Guidelines choices

Top-level navigation uses the system `TabView` (a top tab bar on iPadOS 18, a bottom bar on iPadOS 17), never a custom segmented control. Root and pushed pages use the system navigation bar, large titles and the system back button; Settings lives in the toolbar. Only full-screen session pages, which have no navigation bar, draw `TMTherapyPageHeader`'s close circle. Secondary pills use `ink` text on `actionMuted` for at least 4.5:1 contrast. Destructive pills (`TMTherapyButton(destructive:pill:)`) are system red and follow an explicit confirmation step. Custom text sizes scale with Dynamic Type through `relativeTo:`, and every control keeps at least a 44-point touch target.



`TMTherapyMusicMenu` uses a native Menu/Picker for mutually exclusive music choices. It accepts a string binding, value-only `TherapyMusicOption` labels and a button size (minimum 44 points), exposes the selected value to accessibility, and owns no preferences or playback. Session views map the shared track catalog into options. `TMTherapyPageHeader.trailingContentWidth` reserves centered-title space for trailing session actions so the music control does not overlap the title.

`TMTherapyFoldPanel` renders supplied fold progress as two shaded hinged panels with layer depth. It accepts progress, fold axis, layer count, and fill opacity, and uses flat movement under Reduce Motion. The caller owns gesture recognition, scoring, and demonstration timing. `CameraDisplayGeometry` shares aspect-fit image bounds and normalized-coordinate mapping between camera overlays, excluding letterbox margins.

## Calm camera guidance

`TMSessionBubbleOverlay` (Controls/SessionBubbleOverlay.swift) is the body exercises' only camera guidance (2026-11-17; the former `TMSessionTargetOverlay` with its skeleton, arrows and hold count was removed). From a `SessionBubbleGuide` in normalized image coordinates it draws, with `TMTherapyMergingGuide` in orange: a 44 pt joint circle that flows into the active bubble (`anchor: .second`) from two bubble radii away and is one with it while the joint is inside or a hold runs, a quiet outline for the other bubble, a single circle for a calibration hold on the joint (`captureJoint`, `holdProgress`) or a lone joint (`trackedJoint`), the hold as the guide's arc, and `TMTherapyPopBurst` on the accepted bubble when progress drops from nearly full. The bubble never moves or grows, so the accepted boundary is the drawn outline. It takes values only.

`TMSessionGuideArrows` (Controls/SessionGuideArrows.swift) draws the body guidance arrows under those circles, unchanged from the former overlay: one solid blue curved arrow from the joint to the active bubble, following the limb's turn around `SessionBubbleGuide.pivot` (or bowing away from the image centre without one), fading over the last 60 pt and hidden once the joint arrives or a hold begins; the calibration cue (`SessionMovementCue`) along a fixed path from the limb's start, its passed stretch at 0.2 strength, lengthened to at least about 160 pt and faded in and out over 0.25 s; and the reach direction (`SessionReachArrow`), kept visible at the image edge. A brighter stretch travels toward each open chevron every 1.5 s (still under Reduce Motion). Shafts are 6 pt over an 11 pt `calmUnderlay`, chevron arms about 16 pt back and 28 pt across. `TMSessionBubbleOverlay` takes `movementCue` and `reachArrow` and draws it.

`TMTherapyProgressDots` (Components/TherapyProgressDots.swift) shows repetition progress as one soft dot per repetition, falling back to a thin bar beyond twelve. It displays supplied counts and a VoiceOver label only.

## Light session layout

Arm raise, elbow bend, directional reach and fold towel use the finger-exercise look instead of the black session screen (`TMTherapySessionView` chooses it by activity kind, never by stage, so the preview stays mounted). Practice now uses `TMTherapyExerciseLiveLayout` (see "Shared exercise screens"); the earlier header, fixed side column and `TMTherapyRepetitionPanel` are replaced. Instruction, demonstration and countdowns are light pages over the mounted preview; countdowns use `TMPracticeCountdown`, and rest uses `TMTherapyBreathingRest` (`TMTherapyCountdownDial` is no longer used).

The exercise layout stays visible while the camera gets ready. The light stage pages force the light color scheme, so they stay light in system dark mode.

Compatible additions: `TMMeasuredInstructionText(textColor:)` defaults to white for the dark screens, and light pages pass `.label`. `TMSessionPanel(light:)` draws the grey `panel` instead of a tinted black panel. The 3D examples render on `TherapyPalette.mediaBackground`, the studio grey of the finger demonstrations. The blue and yellow guidance colors use the existing `calmUnderlay` where drawn over camera video.

`TherapyPalette.exerciseBackdrop` is the bright backdrop shared by the 3D examples and their panel.

## Guided gesture controls

Fold towel draws only the current zone with `TMTherapyMergingGuide(anchor: .fixed)`: the zone carries its step glyph, a plain 48 pt hand circle stays on the hand and joins the zone with a 0.25 s ease only while the hand counts as inside, and the release hold is the guide's arc. `TMTherapyStepStrip` shows a short gesture's steps as icons, with the current step named and finished steps checked, on a dark capsule. It takes values only; holds, timing and tracking stay with the caller. Fold towel uses it with `TMTherapyFoldPanel` and `TMTherapyProgressDots`. The former `TMTherapyGuideZone` and `TMTherapyHandCursor` were removed (2026-11-17).

## Daily plan timeline (2026-11-09)

`TherapyPalette` adds `brand`/`onBrand` (rust capsule, white text about 5.9:1), `planCard` (warm off-white card, adaptive), `planMarker` (yellow next-item dot) and `planTrack` (dashed line and hollow dots). `TMTherapyButton(prominent:)` draws the large rust "Mulai Latihan" capsule (96 pt high, 36 pt label), sized to its label instead of filling the width.

Components/TherapyTimeline.swift owns `TMTherapyTimelineRow` (a marker with solid yellow completed connectors and dashed upcoming connectors), `TMTherapyTimelineMarker` (`.current` and `.done` filled yellow, `.upcoming` hollow ring; the card provides the accessible state label), `TMTherapyPlanCard` (title, icon-and-value lines, trailing illustration, one button and one accessibility element whose value names the state) and `TMTherapyFloatingActionDock` (bottom content over a gradient-masked material fade that never takes taps; solid under Reduce Transparency). They take values and actions only; plan order, progress and session launching stay in Features/Home.

`TMTherapyArtwork(fallback:)` shows another asset or `symbol:` image when the named asset is not in the catalog, so a card can reference an illustration that is still being drawn. Plan illustrations are named `plan-<item id>` in Assets.xcassets; they are original artwork drawn for Tuntun (2026-11-09), not third-party assets.

## Shared exercise screens (2026-11-09)

Components/TherapyExerciseScreens.swift owns the five screens every exercise shares. All take values, content and actions; sessions keep their own timing, counting and navigation.

- `TMTherapyExerciseHeading`: grey "Latihan N" eyebrow over a bold centred title.
- `TMTherapyTargetStat` ("8 Repetisi", rust number) and `TMTherapyProgressStat` ("Repetisi 3 / 8"), laid out with `TMTherapyStatRow` and `TMTherapyStatDivider`.
- `TMTherapyInstructionBubble`: a floating white cue bubble, shown only with the floating cue placement.
- `TMTherapyBackButton`: the rust "‹ Kembali" text action.
- `TMTherapyExerciseIntro`: heading, a media slot (the exercise's own demonstration), focus text, a target slot, the safety note and the prominent start.
- `TMTherapyExerciseLiveLayout`: heading with trailing accessories, the camera slot with the cue bubble, the "Ikuti gerakan ini" demonstration column, repetition and set counters (hidden while `calibrating`, their space kept so the camera does not move), and Pause (`TMTherapyButton(pill:brand:)`) and End. The camera keeps one position, so callers layer stage pages and dialogs over it without remounting the preview.
  Heights are proportional: the heading takes about 12% of the screen height, the counters and buttons about 20%, and the camera and demo row the rest, with minimums for small iPads. Counter text and button padding scale with the screen.
- The attached video layout uses a centered heading, enlarged counters and taller controls, with no caption over the video. Finger, Balancing and light guided sessions share these settings. `TMTherapyVideoFooter` hosts the guided calibration cards that require measured reading, aligned to the visible video.
- `TMTherapyLongRest` presents a breathing cue over orange waves and uses static waves under Reduce Motion. The daily plan supplies timing and actions. The waves are `TMTherapyLongRestWaves`, drawn by the `longRestWaves` Metal shader (`LongRestWaves.metal`, `colorEffect`): every display frame up to 60 fps, the breath interpolated between the caller's samples, soft feathered edges. Inhale lifts the bands by 20%, 16% and 12% of the height (back to front, so they fan apart), swells each crest from 5% to 10% and brightens the bands up to 10% toward white; exhale reverses it. A slow crest sway runs on a clock that stops while paused.
- `TMTherapyPauseDialog`: a frosted backdrop with the paused card (set, title, practice time mm:ss, end with an inline confirmation, resume) and an `Extra` slot for caregiver recovery. `confirmingEndInitially` opens it on the confirmation when it came from an End button. It hugs its content and scrolls only when it does not fit.
- `TMTherapySetSummary` with `TherapySetResult`: the set-done and all-done page (rust check, headline, message, results panel, total, optional rest line and actions).
- `TMTherapyFinishActions`: the way on from the all-done page (prominent button, optional repeat link, a slot above for saving or errors). Every exercise, the finger exercises included (`TMFingerSessionCompleteView`), ends on `TMTherapySetSummary` with this block.
- `TMTherapyDemoCaption`: the "Ikuti gerakan ini" / paused pill drawn by the Balancing demonstrations, now one shared view. The `therapyDemoCaptionHidden` environment value hides it where a heading already says it; the intro and live layouts set it.

Compatible additions: `TMTherapyCompletionMark(tint:)` (the screens pass `brand`), `TMTherapyButton(brand:)` for a rust pill, and `TherapyPalette.planPanel`, the warm grey behind demonstration media and the results panel.

`Tools/generate_plan_art.py` draws the plan illustrations for the exercises added on 2026-11-09 (each finger movement, forearm rotation, elbow bend, directional reach, internal rotation and shoulder flexion) from the same figure shapes and colours as the first six, so all `plan-<id>` images match. Rerun it after changing a pose, then `xcodegen generate`.

## Clinician session report (2026-11-12)

`TMSkeletonReplay` (Components/SkeletonReplay.swift) replays supplied poses as a stick figure on a `progressPanel`, with a 52-point terracotta play/pause circle and a scrubber. Poses are normalized points (origin bottom-left, unmirrored), bones are index pairs, and emphasized joints draw the moving limb in `emphasisColor` (default `brand`) over a white underlay, with white-ringed joints; the rest of the body is `planTrack`. It frames the union of all poses, loops while playing, mirrors by default to match the live preview, and starts paused at the midpoint under Reduce Motion. It knows nothing about exercises.

`TMRepClipPlayer` (Components/RepClipPlayer.swift) plays a supplied short silent clip with the same 52-point play/pause circle and scrubber as `TMSkeletonReplay`, on the same `progressPanel` with 24-point corners. It fits the whole frame (`resizeAspect`), loops while playing, mirrors by default to match the live preview, and starts paused at the midpoint under Reduce Motion. It takes a file URL and knows nothing about how the clip was made.

`TMRepValueChart` (Components/RepValueChart.swift) is a single-series Swift Charts bar strip, one bar per repetition. Emphasized bars use `brand` and carry a text marker above, so emphasis is never color alone; the rest use `progressSoftBar`, matching the weekly chart. The caller supplies values, markers and the unit.

## Debug-only UI (2026-11-12)

Components/DebugRibbon.swift exists only in debug builds (`#if DEBUG`). `.debugOnly()` marks any debug control with a dashed `TherapyPalette.debugAccent` (system orange) outline and a diagonal "DEBUG" corner ribbon (`TMDebugRibbon`); the decoration takes no taps and is hidden from VoiceOver, which hears a "Debug only" hint instead. `TMDebugActionButton` is `TMTherapyTextButton` with that marker. Every debug control must sit inside `#if DEBUG` and wear `.debugOnly()`. Session screens overlay their debug "Finish exercise" action on the header's trailing corner, above stage pages and the pause dialog, instead of using `TMTherapyExerciseLiveLayout`'s `accessories`, which would shift the centred heading.

`TMTherapyProgressMetric` (Components/TherapyProgressSummary.swift) is the Progress pages' metric tile: a terracotta icon in a soft square, a large value and a muted unit. `TMTherapyProgressSessionCard` and the movement report share it.


## Demonstration step highlight (2026-11-12)

`TMTherapyDemoHighlight` (Components/TherapyDemoHighlight.swift, `.therapyDemoHighlight(revision:announcement:)`) calls attention to a demonstration panel whose content moved to a new step. Each change of `revision` (never the first value seen) draws a thin 3 pt rust `brand` outline over a 5 pt `calmUnderlay` for about four seconds and pulses the panel gently three times (1.1 s each): a faint ring (55% opacity, 3 to 1 pt) ripples about 10 pt outward from the edge and fades, while the outline glows softly and the panel swells to 1.01. The motion is the signal; there is no badge. It posts the announcement to VoiceOver. Under Reduce Motion only the static outline shows. The ripple draws outside the panel, so callers leave about 10 pt around it. It takes no taps and knows nothing about exercises; the caller decides what a new step is. `TMTherapyExerciseLiveLayout` applies it to its demonstration through `demoRevision` and `demoAnnouncement`, and crossfades `demoTitle` when the revision changes.
