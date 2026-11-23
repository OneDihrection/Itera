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

/// Grey "Latihan 1" above the exercise title, centred.
struct TMTherapyExerciseHeading: View {
    var eyebrow: Text? = nil
    let title: Text

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
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
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

/// "Repetisi 3 / 8": a label, the current value in dark ink and the total in grey.
struct TMTherapyProgressStat: View {
    let label: Text
    let value: Int
    let total: Int
    var textScale: CGFloat = 1

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            label
                .typography(size: 30 * textScale, weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value, format: .number)
                    .typography(size: 56 * textScale, weight: .bold, relativeTo: .largeTitle)
                    .foregroundStyle(TherapyPalette.brandInk)
                Text(verbatim: "/ \(total)")
                    .typography(size: 48 * textScale, weight: .regular, relativeTo: .largeTitle)
                    .foregroundStyle(TherapyPalette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stats side by side with a thin divider between them.
struct TMTherapyStatRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 36) {
            content
        }
    }
}

/// The thin vertical divider used between stats.
struct TMTherapyStatDivider: View {
    var thickness: CGFloat = 1.5

    var body: some View {
        Rectangle()
            .fill(TherapyPalette.outline)
            .frame(width: thickness, height: 64)
            .accessibilityHidden(true)
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

/// The page before an exercise, laid out like the product owner's mockup (2026-11-23): the
/// exercise title and two columns. The left column is the exercise's own demonstration on a pale
/// blue panel; the right column says what the exercise trains, shows the target as stat tiles, and
/// ends with short notes. The panel and the notes end on one line.
///
/// It draws no back control: the caller shows it inside a navigation bar, whose system back
/// button (or bar button) leaves the page. There is no Start button either: the caller opens the
/// session itself. The bar's trailing side carries the one control a caller may need when it
/// cannot go on by itself (resume, or a readiness action), or, after a rest, the countdown; a
/// message explaining it is a small muted line under the title. At accessibility text sizes the
/// columns stack.
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

/// The practice screen: heading, the camera with its cue bubble, the demonstration column,
/// repetition and set counters, and Pause and End.
///
/// The camera keeps one position in this view for every state, so callers can layer stage
/// pages and dialogs over it without remounting the preview.
struct TMTherapyExerciseLiveLayout<Camera: View, Demo: View, Accessories: View>: View {
    let heading: TMTherapyExerciseHeading
    var cue: Text? = nil
    var cuePlacement = TherapyLiveCuePlacement.floating
    let demoTitle: LocalizedStringKey
    let repetitions: (done: Int, goal: Int)
    var sets: (number: Int, total: Int)? = nil
    let pauseTitle: LocalizedStringKey
    let endTitle: LocalizedStringKey
    var pauseDisabled = false
    /// Hides the repetition and set counters while the activity calibrates; their space stays
    /// reserved so the camera does not move.
    var calibrating = false
    var demoWidthFraction: CGFloat = 0.9
    /// Changes whenever the demonstration moves to a new step, which highlights the panel.
    var demoRevision = 0
    /// Spoken to VoiceOver when `demoRevision` changes, usually the new `demoTitle`.
    var demoAnnouncement: String? = nil
    let onPause: () -> Void
    let onEnd: () -> Void
    @ViewBuilder let camera: Camera
    @ViewBuilder let demo: Demo
    /// Small trailing controls beside the heading, such as music or voice.
    @ViewBuilder let accessories: Accessories

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The heading and the counters/buttons row take fixed shares of the height (about 12% and
    // 20%); the camera and demo row takes the rest. The minimums keep a two-line heading and
    // the stacked buttons from clipping on the smallest iPad.
    private static var headerHeightFraction: CGFloat { 0.12 }
    private static var bottomHeightFraction: CGFloat { 0.20 }
    private static var minimumHeaderHeight: CGFloat { 72 }
    private static var minimumBottomHeight: CGFloat { 140 }

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
            let contentHeight = max(0, geometry.size.height - 2 * verticalPadding - 2 * rowSpacing)
            let headerHeight = max(contentHeight * Self.headerHeightFraction, Self.minimumHeaderHeight)
            let bottomHeight = max(contentHeight * Self.bottomHeightFraction, Self.minimumBottomHeight)
            let scale = therapyLayoutScale(for: geometry.size, limits: 0.8...1.3)

            VStack(spacing: rowSpacing) {
                liveHeader
                    .frame(height: headerHeight)

                HStack(alignment: .top, spacing: columnSpacing) {
                    cameraArea
                        .frame(width: cameraWidth)
                    demoColumn(maxMediaWidth: sideWidth * demoWidthFraction)
                        .frame(width: sideWidth)
                }
                .frame(maxHeight: .infinity)

                HStack(alignment: .center, spacing: columnSpacing) {
                    statsSlot(scale: scale)
                        .frame(width: cameraWidth)
                    controls(scale: scale)
                        .frame(width: sideWidth)
                }
                .frame(height: bottomHeight)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, verticalPadding)
        }
        .background(TherapyPalette.canvas)
    }

    @ViewBuilder
    private var liveHeader: some View {
        if Accessories.self == EmptyView.self {
            heading
        } else {
            HStack(spacing: 12) {
                heading

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

    private var demoTitleOffset: CGFloat {
        guard case .video(let bounds) = cuePlacement else {
            return 0
        }
        return bounds?.minY ?? 0
    }

    private func demoColumn(maxMediaWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(demoTitle)
                .typography(size: 24, weight: .bold, relativeTo: .title3)
                .foregroundStyle(TherapyPalette.ink)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: demoRevision)
                .offset(y: demoTitleOffset)

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
    }

    /// No repetitions are counted during calibration, so the counters are left out until practice.
    @ViewBuilder
    private func statsSlot(scale: CGFloat) -> some View {
        if calibrating {
            Color.clear
        } else {
            stats(scale: scale)
        }
    }

    private func stats(scale: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            TMTherapyStatRow {
                repetitionStat(scale: scale)

                if let sets {
                    TMTherapyStatDivider(thickness: cuePlacement.usesVideo ? 3 : 1.5)
                    setStat(sets, scale: scale)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(spacing: 4) {
                repetitionStat(scale: scale)

                if let sets {
                    setStat(sets, scale: scale)
                }
            }
        }
    }

    private func repetitionStat(scale: CGFloat) -> some View {
        TMTherapyProgressStat(
            label: Text("exercise.repetitionsUnit"),
            value: repetitions.done,
            total: repetitions.goal,
            textScale: (cuePlacement.usesVideo ? 1.2 : 1) * scale
        )
    }

    private func setStat(_ sets: (number: Int, total: Int), scale: CGFloat) -> some View {
        TMTherapyProgressStat(
            label: Text("exercise.setsUnit"),
            value: sets.number,
            total: sets.total,
            textScale: (cuePlacement.usesVideo ? 1.2 : 1) * scale
        )
    }

    private func controls(scale: CGFloat) -> some View {
        VStack(spacing: 10 * scale) {
            TMTherapyButton(
                title: pauseTitle,
                symbol: "pause.fill",
                disabled: pauseDisabled,
                pill: true,
                brand: true,
                extraVerticalPadding: cuePlacement.usesVideo ? 4 * scale : 0,
                action: onPause
            )
            TMTherapyButton(
                title: endTitle,
                symbol: "stop.fill",
                secondary: true,
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
                    TMTherapyButton(title: "session.endCancel", secondary: true, pill: true) {
                        confirmingEnd = false
                    }
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

/// "Set 2 selesai!" between sets, or "Latihan selesai" after the last one: a yellow check,
/// a short message, the result of every set and the total.
struct TMTherapySetSummary<Actions: View>: View {
    let heading: TMTherapyExerciseHeading
    let headline: Text
    let message: Text
    let results: [TherapySetResult]
    let total: Text
    /// Optional line under the panel, such as the rest countdown.
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
                        tint: TherapyPalette.brand,
                        checkColor: TherapyPalette.onBrand
                    )
                    .padding(.top, 12 * scale)

                    VStack(spacing: 10 * scale) {
                        headline
                            .typography(size: 40 * scale, weight: .bold, relativeTo: .largeTitle)
                            .accessibilityAddTraits(.isHeader)
                        message
                            .typography(size: 24 * scale, weight: .regular, relativeTo: .title3)
                    }
                    .multilineTextAlignment(.center)

                    panel(scale: scale, width: geometry.size.width)

                    if let footer {
                        footer
                            .typography(size: 22 * scale, weight: .regular, relativeTo: .title3)
                            .foregroundStyle(TherapyPalette.muted)
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

    private func panel(scale: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 20 * scale) {
            HStack(spacing: 0) {
                ForEach(results) { result in
                    if result.number != results.first?.number {
                        Rectangle()
                            .fill(TherapyPalette.outline)
                            .frame(width: 1.5, height: 80 * scale)
                    }
                    setColumn(result, scale: scale)
                        .frame(maxWidth: .infinity)
                }
            }

            total
                .typography(size: 24 * scale, weight: .regular, relativeTo: .title3)
        }
        .padding(.vertical, 28 * scale)
        .padding(.horizontal, 24 * scale)
        .frame(maxWidth: width * 0.8)
        .background(TherapyPalette.planPanel, in: RoundedRectangle(cornerRadius: 28 * scale))
    }

    private func setColumn(_ result: TherapySetResult, scale: CGFloat) -> some View {
        let finished = result.state == .done
        let tint = finished ? TherapyPalette.brand : TherapyPalette.muted

        return VStack(spacing: 6 * scale) {
            HStack(spacing: 10 * scale) {
                Image(systemName: finished ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(tint)
                Text("session.setNumber \(result.number)")
                    .foregroundStyle(finished ? TherapyPalette.ink : TherapyPalette.muted)
            }
            .typography(size: 24 * scale, weight: .medium, relativeTo: .title3)

            Text(verbatim: "\(result.done) / \(result.goal)")
                .typography(size: 36 * scale, weight: .bold, relativeTo: .title)
                .foregroundStyle(tint)

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
