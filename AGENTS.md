# Agent instructions

Every agent working in this repository must read the entire [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md) before planning, reviewing, or changing the project, and follow its architecture, ownership boundaries, coding conventions, platform constraints, and verification requirements. This also applies to delegated agents. Re-read relevant sections when the task changes. If the document is missing or unreadable, stop and report the blocker rather than inventing requirements.

Treat SYSTEM_DESIGN.md as the authoritative project design. Surface conflicts rather than silently departing from it; explicit user instructions take precedence.

## Design system

Every agent doing UI work must inspect `Itera/DesignSystem` and read its README first. Use existing reusable controls and styling from that folder. If no suitable component exists, create a reusable one there before using it. Extend compatible components instead of duplicating controls or styling in feature folders.

Screens may use native SwiftUI layout directly; navigation must use the shared router. Feature views own screen composition; therapy-specific compositions may remain in their feature, using design system controls and styling. Add components only as needed; do not build a speculative library or wrap every SwiftUI primitive.

Design system components accept values, bindings, content, and actions as needed. They must not depend on feature view models, repositories, or exercise logic.

## Project generation

Use the existing Itera project and source directory names. The specification is named project.yml, matching XcodeGen’s default and SYSTEM_DESIGN.md.

Run from the repository root:

```sh
xcodegen generate
```

Make persistent project configuration changes in project.yml, not exclusively in the generated Xcode project. Follow the design's single-target and manual-verification policy. Do not claim physical-device acceptance from a successful Simulator build.

## Current documentation with Context7

Use the ctx7 CLI to fetch current documentation whenever a task concerns a library, framework, SDK, API, CLI tool, or cloud service, including syntax, configuration, migration, library-specific debugging, or setup. Prefer this over web search. Do not use it for ordinary refactoring, scripts from scratch, business logic debugging, code review, or general programming concepts.

1. Resolve the official library name first:
   `npx ctx7@latest library <name> "<full question>"`
2. Select the best matching ID by name, relevance, snippet coverage, source reputation, and benchmark score.
3. Fetch documentation:
   `npx ctx7@latest docs <libraryId> "<full question>"`
4. Use the fetched documentation.

Call library first unless the user supplied an ID in /org/project format. For version-specific questions, use a version ID returned by library. Run no more than three commands per question. Never include secrets in queries.

Run Context7 requests outside the default sandbox. If DNS or network errors occur, rerun outside the sandbox rather than retrying inside it. If quota is exhausted, inform the user and suggest `npx ctx7@latest login` or the CONTEXT7_API_KEY environment variable; do not silently fall back to training data.

## Navigation, typography, and code conventions

All agents must use the shared NavigationRouter for app navigation and sheet/full-screen presentation. Do not create feature-owned NavigationStacks, destination registrations, modal state, or direct dismissal bypasses. Native SwiftUI layout remains allowed.

Use .typography(...) or inherit the root body style for app-authored text. Font names and direct font styling belong only in DesignSystem/Typography.

Keep body focused on composition. Prefer named private computed view properties, using @ViewBuilder for conditional or multiple-view sections, or dedicated subviews for meaningful sections with inputs, bindings, state, reuse, or substantial complexity. Reusable controls belong in DesignSystem; avoid splitting trivial expressions mechanically.

Every newly authored file must have a format-appropriate header with its filename, actual author, and creation date. Use an explicitly supplied author first, otherwise effective git config user.name; ask if neither exists. Never hard-code a team member or use the AI's name. Preserve existing creation authorship. Swift uses Xcode-style // Created by headers; YAML uses comments and Markdown uses HTML comments. Preserve copied binaries and third-party licenses unchanged and document their source separately; never corrupt formats without comment support.

Prefer readable multiline declarations, calls, expressions, and compound conditions when they improve scanning. Put complex arguments and conditions on separate lines. Use generous blank lines between logical steps and declarations while keeping closely related statements together. Expand control-flow bodies onto separate lines; avoid compressed guards, branches, and nested ternaries.

Keep control flow shallow through guard clauses, early returns, and focused, meaningfully named helpers. Preserve clear exhaustive switches when appropriate. Do not mechanically extract trivial expressions or impose arbitrary nesting limits.

Treat readability and runtime performance as equally important. Choose clear algorithms and appropriate data structures, avoid unnecessary repeated work and allocations in frequently executed paths, and preserve the architecture's threading and bounded-work requirements. Base performance-driven complexity on measurements or concrete workload constraints. Document non-obvious tradeoffs and verify that refactors preserve behavior and performance characteristics.

Use /// Markdown API documentation when helpful and // MARK: - sections in longer files. Comment non-obvious purpose, constraints, and lifecycle behavior rather than restating syntax.
