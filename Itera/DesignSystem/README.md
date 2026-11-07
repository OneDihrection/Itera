# Design system

This folder owns reusable UI controls and styling for Itera. Follow the repository [agent instructions](../../AGENTS.md) and [system design](../../SYSTEM_DESIGN.md).

Every agent doing UI work must inspect `Itera/DesignSystem` and read its README first. Use existing reusable controls and styling from that folder. If no suitable component exists, create a reusable one there before using it. Extend compatible components instead of duplicating controls or styling in feature folders.

Screens may use native SwiftUI layout directly; navigation must use the shared router. Feature views own screen composition; therapy-specific compositions may remain in their feature, using design system controls and styling. Add components only as needed; do not build a speculative library or wrap every SwiftUI primitive.

Design system components accept values, bindings, content, and actions as needed. They must not depend on feature view models, repositories, or exercise logic.

Typography owns the bundled Plus Jakarta Sans faces and semantic scaling. Components/TherapyControls.swift owns semantic light/dark surfaces, pastel illustration colors, large action buttons, cards, status labels, metrics, value controls, and error presentation. Components/TherapyArtwork.swift owns illustration panels and accessible image rows; it accepts asset names, values, and actions without exercise logic. Native tabs and navigation stacks remain owned by App/Navigation, and settings use native Form, Picker, Toggle, and DisclosureGroup layouts. Extend these controls when compatible instead of adding feature-local copies. The existing recursive source entry in project.yml includes new components automatically.

## Navigation, typography, and code conventions

All agents must use the shared NavigationRouter for app navigation and sheet/full-screen presentation. Do not create feature-owned NavigationStacks, destination registrations, modal state, or direct dismissal bypasses. Native SwiftUI layout remains allowed.

Use .typography(...) or inherit the root body style for app-authored text. Font names and direct font styling belong only in DesignSystem/Typography.

Keep body focused on composition. Prefer named private computed view properties, using @ViewBuilder for conditional or multiple-view sections, or dedicated subviews for meaningful sections with inputs, bindings, state, reuse, or substantial complexity. Reusable controls belong in DesignSystem; avoid splitting trivial expressions mechanically.

Every newly authored file must have a format-appropriate header with its filename, actual author, and creation date. Use an explicitly supplied author first, otherwise effective git config user.name; ask if neither exists. Never hard-code a team member or use the AI's name. Preserve existing creation authorship. Swift uses Xcode-style // Created by headers; YAML uses comments and Markdown uses HTML comments. Preserve copied binaries and third-party licenses unchanged and document their source separately; never corrupt formats without comment support.

Prefer generous spacing and readable multiline declarations, calls, expressions, and conditions. Use /// Markdown API documentation when helpful and // MARK: - sections in longer files. Comment non-obvious purpose, constraints, and lifecycle behavior rather than restating syntax.

Components/TherapyFeedback.swift owns value-driven progress rings, a timer-only countdown with accessible pause/end actions, bounded success confetti, and large feeling choices. Primary green, secondary sage, and tertiary peach roles are defined in TherapyPalette; mediaBackground matches the fixed rendered hand studio. No component owns session timing, tracking, or persistence.

Components/TherapyProgressArtwork.swift supplies value-driven medallions and native Charts visuals without history/achievement logic. Components/TherapyButtonFeedback.swift supplies a primitive button style whose activation calls an injected environment feedback action, then the original action. The composition root injects the sole audio owner's click method. Controls retain native disabled/activation behavior.

TherapyIconButton in Components/TherapyControls.swift provides a large icon action with an explicit localized accessibility label.

## Session guidance

`MeasuredInstructionText` adapts VisionPoc’s measured, scrollable instruction reader. It accepts rendered text, a request identity, scaled font size, accessibility settings, and a reading-status callback. It owns measurement and presentation pacing only; the session engine decides when to advance. Typography resolves UIKit fonts alongside SwiftUI fonts in Typography.

`ExerciseIllustration` presents a noninteractive SF Symbol and scalable label. Home uses `homeHeading` (64 points) and `homeLabel` (32 points); `SessionButtonStyle` already provides scalable 32-point primary text and a 72-point minimum height.

## Full-screen session presentation

`SessionStageSurface` provides the reference experience’s full-screen surface, 48-point inset, 24-point section spacing, and continuous 36-point border. It accepts content and controls without knowing about session state. `SessionCelebration` provides a cancellable three-second visual celebration and pauses its animation timeline afterward; the caller handles Reduce Motion. Its particle layout was adapted from VisionPoc’s `TherapyClosingSection.swift`.

`TherapyGuideBubble` displays supplied time, progress and target completion without owning tracking or timers. `TherapyAwardReveal` combines the shared badge and bounded confetti with a Reduce Motion-aware entrance. Button activation uses a short press response without changing the original action or accessibility activation.

`TherapyGuideBubble` accepts an optional diameter and outline-only styling for enclosing indicators. Its explicit `showsTimer` input controls timer text and timed progress; labels use an overlay so timer visibility never shifts the tracked circle center.

`TherapyGuideBubble` accepts a completion identity and presentation callback. It reports a completed, visible cue after a cancellable 250 ms settle period, only while active in the foreground. This is presentation acknowledgment, not exercise-time credit. The activity retains its full/zero snapshot until the session receives that matching acknowledgment. Final progress renders without animation lag; partial ring updates interpolate independently of the acceptance clock.

`TherapyMetric` supports compact label spacing for horizontal session headers, retaining its large numeric value and combined accessibility label.

`TherapyAchievementShareSheet` renders a value-driven badge card in memory and exposes the native iPad sharing controller. The shared router owns presentation and completion; the component has no achievement eligibility or persistence logic. Its completion reports actual sharing errors separately from ordinary cancellation.

## Monochrome pages

The home, exercise start, session pages and progress page use a monochrome look: a white `canvas`, black `heroCard` surfaces with `onHero` text, grey `panel` fills, thin `outline` borders and dark `action` pills. `success`, `setDone`/`setDoneFill`, `restRing`/`restTrack` and `challengeFill`/`challengeInk` cover the few coloured states. All are light/dark adaptive tokens in `TherapyPalette`, mapped to system semantic colors (`label`, `systemBackground`, `secondarySystemBackground`, `separator`, `systemGray5`, `systemGreen`, `systemBlue`) wherever one fits.

Existing controls gained compatible options instead of copies: `TherapyButton(pill:)` draws the dark pill (grey when `secondary`), `TherapyIconButton(circle:)` draws the black back/close circle with a 64-point touch target, `TherapyCard(outlined:padding:)` draws a bordered white card, and `TherapyProgressRing(tint:track:lineCap:)` recolours the ring. `TherapyTextButton` is a quiet text action for secondary choices beneath primary buttons.

Components/TherapyPageLayout.swift owns `TherapyPageHeader` (centered title with a leading close circle, for full-screen session pages that have no navigation bar), `TherapyHeroCard`, `TherapyProgramCard` and `TherapyMediaPanel`.

Components/TherapySessionStatus.swift owns `TherapyCompletionMark`, `TherapyTargetTile`, `TherapyNumberedSteps`, `TherapySetRow` (done, next or upcoming) and `TherapyRestCountdown`. They display supplied values only; set progress, rest timing and skipping stay in the session.

Components/TherapyProgressSummary.swift owns `TherapyWeekSummary` (headline band plus seven day cells), `TherapyChallengeCard` (segmented up to ten steps, continuous beyond) and `TherapyAchievementRow`. Callers pass formatted text; no history or achievement rules live here.

### Human Interface Guidelines choices

Top-level navigation uses the system `TabView` (a top tab bar on iPadOS 18, a bottom bar on iPadOS 17), never a custom segmented control. Root and pushed pages use the system navigation bar, large titles and the system back button; Settings lives in the toolbar. Only full-screen session pages, which have no navigation bar, draw `TherapyPageHeader`'s close circle. Secondary pills use `ink` text on `actionMuted` for at least 4.5:1 contrast. Destructive pills (`TherapyButton(destructive:pill:)`) are system red and follow an explicit confirmation step. Custom text sizes scale with Dynamic Type through `relativeTo:`, and every control keeps at least a 44-point touch target.



`TherapyMusicMenu` uses a native Menu/Picker for mutually exclusive music choices. It accepts a string binding, value-only `TherapyMusicOption` labels and a button size (minimum 44 points), exposes the selected value to accessibility, and owns no preferences or playback. Session views map the shared track catalog into options. `TherapyPageHeader.trailingContentWidth` reserves centered-title space for trailing session actions so the music control does not overlap the title.

`TherapyRangeGauge` (Components/TherapyRangeGauge.swift) draws a measured movement range as a start zone, a target zone, and end labels. It takes labels and zone fractions only; the caller decides what the range means.

`TherapyFoldPanel` renders supplied fold progress as two shaded hinged panels with layer depth. It accepts progress, fold axis, layer count, and fill opacity, and uses flat movement under Reduce Motion. The caller owns gesture recognition, scoring, and demonstration timing. `CameraDisplayGeometry` shares aspect-fit image bounds and normalized-coordinate mapping between camera overlays, excluding letterbox margins.

## Calm camera guidance

`SessionTargetOverlay` (Controls/SessionTargetOverlay.swift) draws the arm and reaching guidance over the camera. The target is a soft filled bubble whose outer halo breathes over about four seconds; the home bubble is outline only; a short trail of small chevrons (not a shaft) leads from the joint to the active bubble, brightening in sequence toward it, fading as the joint approaches and hidden once a hold has begun; a thin ring fills around the active bubble while it is held, with no numbers; when a hold is accepted a soft ring expands and fades over 0.6 s (omitted under Reduce Motion). Shape, not color alone, distinguishes the zones, and guidance never uses red. Breathing animates only the halo outside the zone, so the accepted boundary stays the drawn outline, and Reduce Motion freezes it. Colors are `TherapyPalette.calmTeal` and `calmBlue`, fixed tokens for the dim camera feed. Visibility minimums for older patients viewing from 1.5-2.5 m: every shape has a dark underlay (`TherapyPalette.calmUnderlay`) under its colored stroke; the target outline is 10 pt over a mostly opaque fill, the home outline 7 pt, the chevrons 7 pt (about 30 pt wide) over a 14 pt underlay, the hold ring 10 pt over a visible track, and the joint dot 28 pt. The chevron trail fades over the last 60 pt before the bubble. The overlay draws no text labels except the "farthest" reach marker.

`TherapyProgressDots` (Components/TherapyProgressDots.swift) shows repetition progress as one soft dot per repetition, falling back to a thin bar beyond twelve. It displays supplied counts and a VoiceOver label only.

## Light session layout

Arm raise, elbow bend, directional reach and fold towel use the finger-exercise look instead of the black session screen (`TherapySessionView` chooses it by activity kind, never by stage, so the preview stays mounted). Practice shows `TherapyPageHeader` (pause on the leading side; music, repeat, listening icon and stop on the trailing side), one cue line, and the camera beside a 300-point column holding a `TherapyMediaPanel` with the animation (arm raise and elbow bend only) and a `TherapyRepetitionPanel`. Nothing is drawn over the camera except its guidance and a camera-wait `TherapyFeedbackPill`. Instruction, demonstration, rest, feedback and pause are light pages over the mounted preview; the countdown is `TherapyCountdown`.

`TherapyCalmLoader(title:)` is the quiet startup state (breathing circle and a single calm line; static under Reduce Motion) shown while the camera gets ready. The light stage pages force the light color scheme, so they stay light in system dark mode.

Compatible additions: `MeasuredInstructionText(textColor:)` defaults to white for the dark screens, and light pages pass `.label`. `SessionPanel(light:)` draws the grey `panel` instead of a tinted black panel. The 3D examples render on `TherapyPalette.mediaBackground`, the studio grey of the finger demonstrations. `calmTeal` and `calmBlue` now hold the mint and peach of the finger identity (names unchanged); they still sit under `calmUnderlay`, and the visibility minimums above are unchanged.

`TherapyCountdownDial` (Components/TherapyFeedback.swift) is a very large digit inside a thick ring, used for the light pages' preparation, countdown and rest. Owners still publish whole seconds and say whether the clock is running (`running`). While running, the ring sweeps linearly over each second, so progress is continuous without fractional engine time; while waiting (a cue is still being spoken) it rests full and never moves ahead of the digit. `TherapyRepetitionPanel(compact:)` is a shorter card for pages where an illustration should be the larger panel. `TherapyPalette.exerciseBackdrop` is the bright backdrop shared by the 3D examples and their panel.

## Guided gesture controls

`TherapyGuideZone` (Components/TherapyGuideZone.swift) draws a target zone over the camera: a soft fill, a 10 pt outline over a dark underlay, an icon and an optional white hold ring. It fills the frame it is given, so a caller can draw an ellipse matching a normalized acceptance region. An emphasized zone breathes with a halo outside its outline (frozen under Reduce Motion); a quiet zone recedes. `TherapyHandCursor` is a 68 pt hand marker (open hand on a dark backing, pinching hand on a solid mint backing, thicker mint outline while holding). `TherapyStepStrip` shows a short gesture's steps as icons, with the current step named and finished steps checked, on a dark capsule. All take values only; holds, timing and tracking stay with the caller. Fold towel uses them with `TherapyFoldPanel`, `TherapyProgressDots` and the mint and peach calm tokens.
