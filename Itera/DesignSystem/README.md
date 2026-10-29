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

TherapyIconButton in Components/TherapyControls.swift provides a large icon action with an explicit localized accessibility label. Components/TherapyRestBackdrop.swift owns only decorative garden motion, taking a paused value and respecting Reduce Motion and scene activity; it never changes rest duration or session state.

## Session guidance

`MeasuredInstructionText` adapts VisionPoc’s measured, scrollable instruction reader. It accepts rendered text, a request identity, scaled font size, accessibility settings, and a reading-status callback. It owns measurement and presentation pacing only; the session engine decides when to advance. Typography resolves UIKit fonts alongside SwiftUI fonts in Typography.


`ExerciseIllustration` presents a noninteractive SF Symbol and scalable label. Home uses `homeHeading` (64 points) and `homeLabel` (32 points); `SessionButtonStyle` already provides scalable 32-point primary text and a 72-point minimum height.

## Full-screen session presentation

`SessionStageSurface` provides the reference experience’s full-screen surface, 48-point inset, 24-point section spacing, and continuous 36-point border. It accepts content and controls without knowing about session state. `SessionCelebration` provides a cancellable three-second visual celebration and pauses its animation timeline afterward; the caller handles Reduce Motion. Its particle layout was adapted from VisionPoc’s `TherapyClosingSection.swift`.
