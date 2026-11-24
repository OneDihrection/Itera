//
//  TherapyExerciseScreens.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

// The five screens every exercise shares: intro, live practice, pause, set done and all done.
// They take values, content and actions only; sessions keep their own timing and progression.

// MARK: - Layout scale

/// Scales sizes against an 11-inch iPad landscape reference (1194 x 834) so screens fill
/// larger and smaller iPads proportionally.
private func therapyLayoutScale(
    for size: CGSize,
    limits: ClosedRange<CGFloat>
) -> CGFloat {
    let proportional = min(size.width / 1194, size.height / 834)

    return min(max(proportional, limits.lowerBound), limits.upperBound)
}

// MARK: - Heading

/// Grey "Latihan 1" above the exercise title, centred, with an optional muted line under it.
struct TMTherapyExerciseHeading: View {
    var eyebrow: Text? = nil
    let title: Text
    /// A muted line under the title, such as "Belum termasuk latihan" while calibrating.
    var subtitle: Text? = nil

    var body: some View {
        VStack(spacing: 4) {
            if let eyebrow {
                eyebrow
                    .typography(size: 22, weight: .regular, relativeTo: .title3)
                    .foregroundStyle(TherapyPalette.muted)
            }

            title
                .typography(size: 42, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(TherapyPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                subtitle
                    .typography(size: 22, weight: .regular, relativeTo: .title3)
                    .foregroundStyle(TherapyPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

extension TMTherapyExerciseHeading {
    /// "Persiapan Gerakan" over "Belum termasuk latihan", while any exercise calibrates.
    static var calibration: TMTherapyExerciseHeading {
        TMTherapyExerciseHeading(
            title: Text("session.calibrationHeading"),
            subtitle: Text("session.calibrationSubtitle")
        )
    }
}

// MARK: - Stats

/// A large dark number with its unit beside it, such as "8 Repetisi".
struct TMTherapyTargetStat: View {
    let value: Int
    let unit: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(value, format: .number)
                .typography(size: 64, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(TherapyPalette.brandInk)
            unit
                .typography(size: 30, weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Repetisi 3 / 8": a label on the leading edge, and on the trailing edge the current value in
/// dark ink and the total in grey, so stacked stats line up their numbers.
///
/// The value rolls to each new count. A prominent stat shows its value bold in `brandInk` and
/// turns it green once it reaches the total; a secondary one (`prominent: false`, for context
/// such as the set) steps down to semibold `ink` and never turns green. Digits are monospaced
/// so "/ total" never shifts as the count changes. `labelScale` sizes the label apart from the
/// number, so a small stat keeps a readable label.
struct TMTherapyProgressStat: View {
    let label: Text
    let value: Int
    let total: Int
    var textScale: CGFloat = 1
    /// Defaults to `textScale`.
    var labelScale: CGFloat? = nil
    var prominent = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reachedTotal: Bool {
        prominent && total > 0 && value >= total
    }

    private var valueColor: Color {
        if reachedTotal {
            return TherapyPalette.success
        }

        return prominent ? TherapyPalette.brandInk : TherapyPalette.ink
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            label
                .typography(size: 30 * (labelScale ?? textScale), weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.muted)

            Spacer(minLength: 18)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value, format: .number)
                    .typography(size: 56 * textScale, weight: prominent ? .bold : .semiBold, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .contentTransition(.numericText())

                Text(verbatim: "/ \(total)")
                    .typography(size: 48 * textScale, weight: .regular, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .foregroundStyle(TherapyPalette.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Instruction bubble

/// A floating cue bubble over the camera.
struct TMTherapyInstructionBubble: View {
    static let baseFontSize: CGFloat = 24

    let text: Text

    var body: some View {
        text
            .typography(size: Self.baseFontSize, weight: .medium, relativeTo: .title3)
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Intro

/// The intro's bottom actions: Pause (or "Lanjutkan latihan" while `paused`), End and Skip.
struct TMTherapyIntroFlowActions {
    var paused = false
    var disabled = false
    let pause: () -> Void
    let stop: () -> Void
    let skip: () -> Void
}

/// The page before an exercise, laid out like the product owner's mockup (2026-11-23): the
/// exercise title and two columns. The left column is the exercise's own demonstration on a pale
/// blue panel; the right column says what the exercise trains, shows the target as stat tiles, and
/// ends with short notes. The panel and the notes end on one line.
///
/// It draws no back control and no Start button: the caller opens the session itself, and
/// `flowActions` puts underlined Pause, End and Skip text actions at the bottom of the page, as on
/// the rests. The caller shows it inside a navigation bar, whose trailing side carries the one
/// control a caller may need when it cannot go on by itself (a readiness action), or, after a
/// rest, the countdown; a message explaining it is a small muted line under the title. At
/// accessibility text sizes the columns stack.
struct TMTherapyExerciseIntro<Media: View, Targets: View, Notes: View>: View {
    let heading: TMTherapyExerciseHeading
    let focusTitle: LocalizedStringKey
    let focus: Text
    var message: Text? = nil
    var countdownSeconds: Int? = nil
    /// Shown only when set, as a yellow capsule in the navigation bar's trailing side.
    var actionTitle: LocalizedStringKey? = nil
    var actionDisabled = false
    var onAction: () -> Void = {}
    /// Pause, End and Skip at the bottom of the page, when the caller passes them.
    var flowActions: TMTherapyIntroFlowActions? = nil
    @ViewBuilder let media: Media
    /// The stat tiles, laid out in one row of equal widths.
    @ViewBuilder let targets: Targets
    /// The short notes under the targets, such as safety and voice control.
    @ViewBuilder let notes: Notes

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { proxy in
            let metrics = IntroMetrics(size: proxy.size)

            ScrollView {
                Group {
                    if typeSize.isAccessibilitySize {
                        stackedPage(metrics)
                    } else {
                        columnsPage(metrics)
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            flowActionRow
        }
        .background(TherapyPalette.progressCanvas)
        .toolbar {
            // The mockup leaves the top right empty; it holds a control only when needed, and
            // being in the bar it never pushes the page below the screen.
            ToolbarItem(placement: .topBarTrailing) {
                actionRow
            }
        }
    }

    // MARK: - Layouts

    /// Landscape at ordinary text sizes, spaced as in the mockup.
    private func columnsPage(_ metrics: IntroMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
                .padding(.bottom, metrics.titleToContent)

            HStack(alignment: .top, spacing: metrics.columnGap) {
                mediaPanel
                    .frame(width: metrics.mediaWidth)
                    .frame(minHeight: metrics.mediaMinHeight, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    focusSection(metrics)
                        .padding(.bottom, metrics.focusToTargets)

                    targetRow

                    Spacer(minLength: metrics.targetsToNotes)

                    notesStack
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // Both columns take the taller one's height, so the panel ends with the notes.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Accessibility text sizes: one scrolling column, so nothing is clipped.
    private func stackedPage(_ metrics: IntroMetrics) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            titleBlock

            mediaPanel
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)

            focusSection(metrics)

            targetRow

            notesStack
        }
    }

    // MARK: - Sections

    /// The title, with the caller's message under it only when there is one.
    private var titleBlock: some View {
        VStack(spacing: 8) {
            heading

            if let message {
                message
                    .typography(.footnote)
                    .foregroundStyle(TherapyPalette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var mediaPanel: some View {
        TherapyPalette.historyCard
            .overlay {
                media
                    .environment(\.therapyDemoCaptionHidden, true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func focusSection(_ metrics: IntroMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.focusTitleToText) {
            Text(focusTitle)
                .typography(size: 32, weight: .bold, relativeTo: .title2)
                .accessibilityAddTraits(.isHeader)

            focus
                .typography(size: 26, weight: .regular, relativeTo: .title3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(TherapyPalette.ink)
    }

    private var targetRow: some View {
        HStack(alignment: .top, spacing: 16) {
            targets
        }
    }

    private var notesStack: some View {
        VStack(spacing: 16) {
            notes
        }
    }

    @ViewBuilder
    private var flowActionRow: some View {
        if let flowActions {
            TMTherapyFlowActions(
                paused: flowActions.paused,
                disabled: flowActions.disabled,
                pause: flowActions.pause,
                stop: flowActions.stop,
                skip: flowActions.skip
            )
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(TherapyPalette.progressCanvas)
        }
    }

    /// The countdown after a rest, or the caller's action. Nothing at all when there is
    /// neither, so the page matches the mockup.
    @ViewBuilder
    private var actionRow: some View {
        if let countdownSeconds {
            countdownCapsule(countdownSeconds)
        } else if let actionTitle {
            actionButton(actionTitle)
        }
    }

    /// A yellow capsule sized for the navigation bar.
    private func actionButton(_ title: LocalizedStringKey) -> some View {
        Button(action: onAction) {
            Text(title)
                .typography(size: 18, weight: .semiBold, relativeTo: .headline)
                .foregroundStyle(TherapyPalette.onBrand)
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .background(TherapyPalette.brand, in: Capsule())
                .fixedSize()
                .contentShape(Capsule())
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .disabled(actionDisabled)
        .opacity(actionDisabled ? 0.5 : 1)
    }

    private func countdownCapsule(_ seconds: Int) -> some View {
        Text(
            verbatim: Duration
                .seconds(seconds)
                .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
        )
        .typography(size: 24, weight: .bold, relativeTo: .title2)
        .monospacedDigit()
        .foregroundStyle(TherapyPalette.onBrand)
        .padding(.horizontal, 18)
        .frame(minHeight: 40)
        .background(TherapyPalette.brand, in: Capsule())
        .accessibilityLabel("calibration.countdown")
        .accessibilityValue(Text(seconds, format: .number))
    }
}

/// The intro's gaps, measured on the product owner's 1366 × 1024 pt mockup (a 12.9-inch iPad)
/// and scaled to the screen: horizontal ones by width, vertical ones by the smaller ratio so
/// they never outgrow a shorter screen. Type sizes stay fixed for legibility.
private struct IntroMetrics {
    private static let reference = CGSize(width: 1366, height: 1024)
    /// Where the status bar and an inline navigation bar end, which the mockup's measurements
    /// include but the safe area does not.
    private static let navigationBarBottom: CGFloat = 74

    let width: CGFloat
    let scale: CGFloat

    init(size: CGSize) {
        width = size.width
        scale = min(
            size.width / Self.reference.width,
            size.height / Self.reference.height
        )
    }

    private func horizontal(_ value: CGFloat) -> CGFloat {
        width * value / Self.reference.width
    }

    private func vertical(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    /// Page margin to the panel's left edge and from the right column's right edge (80 pt).
    var horizontalPadding: CGFloat { horizontal(80) }
    /// The panel width (501 pt) and the gap to the right column (61 pt).
    var mediaWidth: CGFloat { horizontal(501) }
    var columnGap: CGFloat { horizontal(61) }
    /// The panel's height before the column decides (577 pt tall at 501 wide).
    var mediaMinHeight: CGFloat { mediaWidth * 577 / 501 * 0.85 }

    /// The title's top (about 135 pt on screen), below the navigation bar, which ends 74 pt down
    /// (a 24 pt status bar and a 50 pt bar) where the mockup drew its back circle.
    var topPadding: CGFloat { vertical(135 - Self.navigationBarBottom) }
    /// Title baseline area to the panel and "Fokus Latihan" (about 80 pt).
    var titleToContent: CGFloat { vertical(78) }
    var focusTitleToText: CGFloat { vertical(16) }
    var focusToTargets: CGFloat { vertical(42) }
    var targetsToNotes: CGFloat { vertical(78) }
    var cardGap: CGFloat { 16 }
    var bottomPadding: CGFloat { vertical(40) }
}

// MARK: - Live practice

enum TherapyLiveCuePlacement {
    case floating
    case video(CGRect?)

    var usesVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

/// The practice screen: the exercise title, the camera filling the left column, and beside it
/// the demonstration, the repetition and set counters (`TMTherapyProgressStat`), and Pause and End.
///
/// The camera keeps one position in this view for every state, so callers can layer stage
/// pages and dialogs over it without remounting the preview.
struct TMTherapyExerciseLiveLayout<Camera: View, Demo: View, Accessories: View>: View {
    let heading: TMTherapyExerciseHeading
    var cue: Text? = nil
    var cuePlacement = TherapyLiveCuePlacement.floating
    let repetitions: (done: Int, goal: Int)
    var sets: (number: Int, total: Int)? = nil
    let pauseTitle: LocalizedStringKey
    let endTitle: LocalizedStringKey
    var pauseDisabled = false
    /// Hides the counters while the activity calibrates; their space stays reserved so the
    /// demonstration does not move when practice starts.
    var calibrating = false
    var demoWidthFraction: CGFloat = 0.9
    /// Changes whenever the demonstration moves to a new step, which highlights the panel.
    var demoRevision = 0
    /// Spoken to VoiceOver when `demoRevision` changes.
    var demoAnnouncement: String? = nil
    let onPause: () -> Void
    let onEnd: () -> Void
    @ViewBuilder let camera: Camera
    @ViewBuilder let demo: Demo
    /// Small trailing controls beside the heading, such as music or voice.
    @ViewBuilder let accessories: Accessories

    // The heading and the Pause/End block take fixed shares of the height (about 12% and 20%);
    // the demonstration takes what the counters leave. The minimums keep a two-line heading
    // and the stacked buttons from clipping on the smallest iPad.
    private static var headerHeightFraction: CGFloat { 0.12 }
    private static var controlsHeightFraction: CGFloat { 0.20 }
    private static var minimumHeaderHeight: CGFloat { 72 }
    private static var minimumControlsHeight: CGFloat { 140 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let inset = min(20, width * 0.015)
            let columnSpacing = min(16, width * 0.012)
            let availableWidth = max(0, width - 2 * inset - columnSpacing)
            let sideWidth = min(460, availableWidth * 0.35)
            let cameraWidth = availableWidth - sideWidth
            let rowSpacing = columnSpacing * 0.5
            let verticalPadding = min(10, geometry.size.height * 0.012)
            let contentHeight = max(0, geometry.size.height - 2 * verticalPadding - rowSpacing)
            let headerHeight = max(contentHeight * Self.headerHeightFraction, Self.minimumHeaderHeight)
            let controlsHeight = max(contentHeight * Self.controlsHeightFraction, Self.minimumControlsHeight)
            let scale = therapyLayoutScale(for: geometry.size, limits: 0.8...1.3)

            VStack(spacing: rowSpacing) {
                liveHeader
                    .frame(height: headerHeight)

                HStack(alignment: .top, spacing: columnSpacing) {
                    cameraArea
                        .frame(width: cameraWidth)

                    sideColumn(
                        maxMediaWidth: sideWidth * demoWidthFraction,
                        spacing: columnSpacing,
                        controlsHeight: controlsHeight,
                        scale: scale
                    )
                    .frame(width: sideWidth)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, verticalPadding)
        }
        .background(TherapyPalette.canvas)
    }

    /// The exercise title and its subtitle: the "Latihan N" eyebrow is left to the pages around
    /// practice.
    @ViewBuilder
    private var liveHeader: some View {
        let title = TMTherapyExerciseHeading(title: heading.title, subtitle: heading.subtitle)

        if Accessories.self == EmptyView.self {
            title
        } else {
            HStack(spacing: 12) {
                title

                HStack(spacing: 12) {
                    accessories
                }
                .layoutPriority(1)
            }
        }
    }

    private var cameraArea: some View {
        camera
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(alignment: .bottom) {
                // The video-attached layout carries no caption; narration speaks the cue.
                if let cue, !cuePlacement.usesVideo {
                    TMTherapyInstructionBubble(text: cue).padding(24)
                }
            }
    }

    private func sideColumn(
        maxMediaWidth: CGFloat,
        spacing: CGFloat,
        controlsHeight: CGFloat,
        scale: CGFloat
    ) -> some View {
        VStack(spacing: spacing) {
            demoMedia(maxMediaWidth: maxMediaWidth)

            progressStats(scale: scale)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)

            controls(scale: scale)
                .frame(height: controlsHeight)
        }
    }

    /// The square demonstration, shrinking to the height the counters and buttons leave.
    private func demoMedia(maxMediaWidth: CGFloat) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: maxMediaWidth)
            .overlay {
                demo
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.therapyDemoCaptionHidden, true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .therapyDemoHighlight(revision: demoRevision, announcement: demoAnnouncement)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A smaller "Set n / total" over a larger "Repetisi n / goal", numbers on the trailing edge.
    /// Only the repetitions change during a set, so they lead; a single-set exercise shows no
    /// set row. Always stacked, so a wider count never reflows the column mid-set. No repetitions
    /// are counted during calibration, so the counters are hidden until practice.
    private func progressStats(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            if let sets, sets.total > 1 {
                TMTherapyProgressStat(
                    label: Text("exercise.setsUnit"),
                    value: sets.number,
                    total: sets.total,
                    textScale: scale * 0.65,
                    labelScale: scale * 0.85,
                    prominent: false
                )
            }

            repetitionStat(scale: scale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(calibrating ? 0 : 1)
        .accessibilityHidden(calibrating)
    }

    private func repetitionStat(scale: CGFloat) -> some View {
        let goal = max(0, repetitions.goal)

        return TMTherapyProgressStat(
            label: Text("exercise.repetitionsUnit"),
            value: min(max(0, repetitions.done), goal),
            total: goal,
            textScale: scale * 1.15
        )
    }

    private func controls(scale: CGFloat) -> some View {
        VStack(spacing: 10 * scale) {
            TMTherapyButton(
                title: pauseTitle,
                symbol: "pause.fill",
                disabled: pauseDisabled,
                plain: true,
                extraVerticalPadding: cuePlacement.usesVideo ? 4 * scale : 0,
                action: onPause
            )
            TMTherapyButton(
                title: endTitle,
                symbol: "stop.fill",
                destructive: true,
                pill: true,
                extraVerticalPadding: cuePlacement.usesVideo ? 4 * scale : 0,
                action: onEnd
            )
        }
    }
}

// MARK: - Pause dialog

/// "Latihan dijeda" over a frosted copy of the session, with practice time so far.
/// Ending asks once more inside the card before calling `onEnd`.
struct TMTherapyPauseDialog<Extra: View>: View {
    var setLabel: Text? = nil
    let title: Text
    let elapsedSeconds: Int
    var resumeDisabled = false
    /// Opens straight on the end confirmation, when the dialog came from an End button.
    var confirmingEndInitially = false
    let onEnd: () -> Void
    let onResume: () -> Void
    /// Recovery controls outside the pause card, only when resuming is blocked.
    @ViewBuilder let extra: Extra

    @State private var confirmingEnd = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.25))
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                card
                extra
            }
            .frame(maxWidth: 800)
            .padding(32)
        }
        .onAppear {
            confirmingEnd = confirmingEndInitially
        }
    }

    /// Hugs its content; scrolls only when it does not fit, such as at very large text sizes.
    private var card: some View {
        ViewThatFits(in: .vertical) {
            cardContent
            ScrollView {
                cardContent
            }
        }
        .background(TherapyPalette.canvas, in: RoundedRectangle(cornerRadius: 32))
    }

    private var cardContent: some View {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    Image(systemName: "pause.fill")
                        .typography(size: 20, weight: .bold)
                        .foregroundStyle(TherapyPalette.brand)
                        .frame(width: 48, height: 48)
                        .background(TherapyPalette.planPanel, in: Circle())
                        .accessibilityHidden(true)
                    Text("session.pausedTitle")
                        .typography(size: 36, weight: .bold, relativeTo: .title)
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(spacing: 4) {
                    if let setLabel {
                        setLabel
                            .typography(size: 22, weight: .regular, relativeTo: .title3)
                            .foregroundStyle(TherapyPalette.muted)
                    }
                    title
                        .typography(size: 22, weight: .medium, relativeTo: .title3)
                }

                Text(Self.clock(elapsedSeconds))
                    .typography(size: 72, weight: .bold, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .accessibilityLabel(Text("session.elapsedTime \(elapsedSeconds / 60) \(elapsedSeconds % 60)"))

                actions
                    .padding(.top, 16)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(TherapyPalette.ink)
            .padding(40)
    }

    @ViewBuilder
    private var actions: some View {
        if confirmingEnd {
            VStack(spacing: 14) {
                Text("session.endConfirmMessage")
                    .typography(.body)
                HStack(spacing: 16) {
                    TMTherapyButton(
                        title: "session.endCancel",
                        secondary: true,
                        pill: true,
                        action: cancelEnd
                    )
                    TMTherapyButton(title: "session.endConfirm", pill: true, brand: true, action: onEnd)
                }
            }
        } else {
            HStack(spacing: 16) {
                TMTherapyButton(title: "session.endSession", secondary: true, pill: true) {
                    confirmingEnd = true
                }
                TMTherapyButton(
                    title: "session.resumeExercise",
                    symbol: "play.fill",
                    disabled: resumeDisabled,
                    pill: true,
                    brand: true,
                    action: onResume
                )
            }
        }
    }

    /// Opened from an End button, the session paused only to ask, so Cancel closes the dialog
    /// and resumes in one tap. Reached from this card's own End, or while resuming is blocked,
    /// Cancel goes back to the paused card.
    private func cancelEnd() {
        guard confirmingEndInitially, !resumeDisabled else {
            confirmingEnd = false
            return
        }

        onResume()
    }

    private static func clock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

// MARK: - Set summary

/// One set in the results panel.
struct TherapySetResult: Identifiable, Equatable {
    enum State: Equatable {
        case done
        case current
        case upcoming
    }

    let number: Int
    let done: Int
    let goal: Int
    let state: State

    var id: Int {
        number
    }
}

/// "Hebat! Kamu sudah menyelesaikan set 2" between sets, or "Latihan selesai" after the last
/// one: a green check, the total, an optional message, the result of every set and the rest line.
struct TMTherapySetSummary<Actions: View>: View {
    let heading: TMTherapyExerciseHeading
    let headline: Text
    /// The total under the headline. Its strongly emphasized runs (`**…**` in the String
    /// Catalog) are drawn in green.
    let total: AttributedString
    /// An optional line under the total, such as a scripted summary or the stopped message.
    var message: Text? = nil
    let results: [TherapySetResult]
    /// Optional line under the panel, such as the rest countdown, led by a clock.
    var footer: Text? = nil
    @ViewBuilder let actions: Actions

    var body: some View {
        GeometryReader { geometry in
            let scale = therapyLayoutScale(for: geometry.size, limits: 0.8...1.4)

            ScrollView {
                VStack(spacing: 28 * scale) {
                    Spacer(minLength: 0)

                    heading

                    TMTherapyCompletionMark(
                        size: 124 * scale,
                        tint: TherapyPalette.success,
                        checkColor: .white
                    )
                    .padding(.top, 12 * scale)

                    VStack(spacing: 10 * scale) {
                        headline
                            .typography(size: 40 * scale, weight: .bold, relativeTo: .largeTitle)
                            .accessibilityAddTraits(.isHeader)

                        Text(emphasizedTotal)
                            .typography(size: 24 * scale, weight: .regular, relativeTo: .title3)

                        if let message {
                            message
                                .typography(size: 22 * scale, weight: .regular, relativeTo: .title3)
                                .foregroundStyle(TherapyPalette.muted)
                        }
                    }
                    .multilineTextAlignment(.center)

                    panel(scale: scale, width: geometry.size.width)

                    if let footer {
                        Label {
                            footer
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .typography(size: 22 * scale, weight: .regular, relativeTo: .title3)
                        .monospacedDigit()
                    }

                    actions

                    Spacer(minLength: 0)
                }
                .foregroundStyle(TherapyPalette.ink)
                .padding(.horizontal, 48 * scale)
                .padding(.vertical, 24 * scale)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
    }

    /// The total with its bold figures in green, which keeps about 7:1 on white.
    private var emphasizedTotal: AttributedString {
        var text = total

        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].foregroundColor = TherapyPalette.green
        }

        return text
    }

    /// The card hugs its sets, up to 65% of the width. When the sets need more room than that
    /// (the finger all-done page lists every movement's sets), they share the capped width.
    /// The background belongs to each candidate, not the capping frame: a `maxWidth` frame takes
    /// all the width it is offered, which would stretch the card again.
    private func panel(scale: CGFloat, width: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            card(setRow(scale: scale, fills: false), scale: scale)
            card(setRow(scale: scale, fills: true), scale: scale)
        }
        .frame(maxWidth: width * 0.65)
    }

    private func card(_ row: some View, scale: CGFloat) -> some View {
        row
            .padding(.vertical, 28 * scale)
            .padding(.horizontal, 24 * scale)
            .background(TherapyPalette.historyCard, in: RoundedRectangle(cornerRadius: 28 * scale))
    }

    /// Fitted columns share one minimum width so the sets stay evenly spaced; filling columns
    /// split whatever width the card offers.
    private func setRow(scale: CGFloat, fills: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(results) { result in
                if result.number != results.first?.number {
                    Rectangle()
                        .fill(TherapyPalette.outline)
                        .frame(width: 1.5, height: 80 * scale)
                }

                if fills {
                    setColumn(result, scale: scale)
                        .frame(maxWidth: .infinity)
                } else {
                    setColumn(result, scale: scale)
                        .frame(minWidth: 150 * scale)
                        .padding(.horizontal, 12 * scale)
                }
            }
        }
    }

    private func setColumn(_ result: TherapySetResult, scale: CGFloat) -> some View {
        let finished = result.state == .done

        return VStack(spacing: 6 * scale) {
            HStack(spacing: 10 * scale) {
                Image(systemName: finished ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(finished ? TherapyPalette.success : TherapyPalette.muted)
                Text("session.setNumber \(result.number)")
                    .foregroundStyle(finished ? TherapyPalette.ink : TherapyPalette.muted)
            }
            .typography(size: 24 * scale, weight: .medium, relativeTo: .title3)

            Text(verbatim: "\(result.done) / \(result.goal)")
                .typography(size: 36 * scale, weight: .bold, relativeTo: .title)
                .foregroundStyle(finished ? TherapyPalette.green : TherapyPalette.muted)

            Text("session.repetitionsLower")
                .typography(size: 20 * scale, weight: .regular, relativeTo: .callout)
                .foregroundStyle(TherapyPalette.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Finish actions

/// The way on from the all-done page: a prominent button, an optional "repeat" link under it,
/// and a slot above for saving progress or a save error. Every exercise ends with this block.
struct TMTherapyFinishActions<Status: View>: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    var disabled = false
    var repeatTitle: LocalizedStringKey? = nil
    var onRepeat: (() -> Void)? = nil
    let action: () -> Void
    @ViewBuilder let status: Status

    var body: some View {
        VStack(spacing: 12) {
            status

            TMTherapyButton(
                title: title,
                symbol: symbol,
                disabled: disabled,
                prominent: true,
                action: action
            )

            if let repeatTitle, let onRepeat {
                TMTherapyTextButton(
                    title: repeatTitle,
                    symbol: "arrow.clockwise",
                    action: onRepeat
                )
            }
        }
    }
}

extension TMTherapyFinishActions where Status == EmptyView {
    init(
        title: LocalizedStringKey,
        symbol: String? = nil,
        disabled: Bool = false,
        repeatTitle: LocalizedStringKey? = nil,
        onRepeat: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            symbol: symbol,
            disabled: disabled,
            repeatTitle: repeatTitle,
            onRepeat: onRepeat,
            action: action
        ) {
            EmptyView()
        }
    }
}

// MARK: - Demonstration caption

private struct DemoCaptionHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True where a heading already says "Ikuti gerakan ini", so demonstrations omit their own
    /// caption pill. Set by the shared intro and live layouts.
    var therapyDemoCaptionHidden: Bool {
        get { self[DemoCaptionHiddenKey.self] }
        set { self[DemoCaptionHiddenKey.self] = newValue }
    }
}

/// The small "Ikuti gerakan ini" (or paused) pill at the bottom of a demonstration.
struct TMTherapyDemoCaption: View {
    let paused: Bool

    @Environment(\.therapyDemoCaptionHidden) private var hidden

    var body: some View {
        if !hidden {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: paused ? "pause.fill" : "waveform.path")
                    Text(paused ? "balance.animationPaused" : "balance.animationPlaying")
                }
                .typography(.footnote)
                .foregroundStyle(TherapyPalette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
            }
        }
    }
}
