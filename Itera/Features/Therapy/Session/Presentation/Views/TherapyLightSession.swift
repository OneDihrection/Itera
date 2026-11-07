//
//  TherapyLightSession.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import SwiftUI

// The light, finger-exercise look for arm raise, elbow bend, directional reach and fold towel.
// The camera stays in one place in the view tree: the practice layout is always mounted, and the
// stage pages below are overlays on top of it (SYSTEM_DESIGN.md section 5).

// MARK: - Practice layout

extension TherapySessionView {
    /// Header, one cue line, then the camera beside the animation and repetition panels.
    var lightLayout: some View {
        VStack(spacing: 14) {
            lightHeader
            lightCue
            lightMainRow
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 32)
        .accessibilityHidden(hasFullScreenPresentation)
    }

    private var lightHeader: some View {
        TherapyPageHeader(
            title: lightTitle,
            leadingTitle: "session.pause",
            leadingSymbol: "pause.fill",
            leadingAction: { model.command(.pause) },
            trailingContentWidth: 220
        )
        .overlay(alignment: .trailing) {
            HStack(spacing: 4) {
                TherapyMusicMenu(
                    selection: $musicTrack,
                    options: ExerciseMusicTrack.allCases.map {
                        TherapyMusicOption(id: $0.rawValue, title: LocalizedStringKey($0.titleKey))
                    },
                    size: 44
                )
                TherapyIconButton(title: "session.repeat", symbol: "speaker.wave.2.fill", size: 44, circle: true) {
                    model.command(.repeatInstruction)
                }
                Image(systemName: model.listening ? "mic.fill" : "mic.slash")
                    .typography(size: 20, weight: .semiBold)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(Text(model.listening ? "session.listening" : "home.voiceUnavailable"))
                TherapyIconButton(title: "therapy.session.stop", symbol: "stop.fill", size: 44, circle: true) {
                    model.command(.stop)
                }
            }
        }
    }

    private var lightTitle: LocalizedStringKey {
        guard let activity = model.snapshot.activity else {
            return ""
        }

        var name = lightString(kindKeyName(activity.kind))

        if activity.hasSide {
            name += " · " + lightString(activity.side == .left ? "session.left" : "session.right")
        }

        return "session.setTitle \(model.snapshot.setNumber) \(name)"
    }

    private var lightCue: some View {
        let copy = SessionGuidanceCopy(phrase: lightString(primaryMovementCue))

        return VStack(spacing: 6) {
            Text(verbatim: copy.main)
                .typography(size: 36, weight: .semiBold, relativeTo: .title)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let support = copy.support ?? (reservesSupportLine ? " " : nil) {
                Text(verbatim: support)
                    .typography(size: 22, weight: .medium, relativeTo: .title3)
                    .foregroundStyle(TherapyPalette.muted)
            }

            lightStatusLine
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: copy.main)
        .accessibilityElement(children: .combine)
    }

    /// Reach cues alternate between one and two lines; reserving the second keeps the camera still.
    private var reservesSupportLine: Bool {
        guard case .reach = model.snapshot.presentation else {
            return false
        }

        return true
    }

    @ViewBuilder
    private var lightStatusLine: some View {
        switch model.snapshot.presentation {
        case .reach(let reach):
            // Calibration shows no status; the line appears with rehearsal and practice only.
            Text(reach.rehearsal ? "session.rehearsal" : "session.reachRound \(reach.round)")
                .monospacedDigit()
                .typography(size: 22, weight: .regular, relativeTo: .body)
                .foregroundStyle(TherapyPalette.muted)
                .opacity(showsReachStatus(reach) ? 1 : 0)
        case .towel(let towel) where towel.phase == .practice:
            Text("towel.foldNumber \(towel.foldIndex + 1)")
                .typography(size: 22, weight: .regular, relativeTo: .body)
                .foregroundStyle(TherapyPalette.muted)
        case .timed(let practice):
            Text("session.practiceSeconds \(Int(practice.seconds)) \(Int(practice.goal))")
                .typography(size: 22, weight: .regular, relativeTo: .body)
                .foregroundStyle(TherapyPalette.muted)
        default:
            EmptyView()
        }
    }

    private func showsReachStatus(_ reach: ReachSnapshot) -> Bool {
        reach.phase == .rehearsal || reach.phase == .practice
    }

    private var lightMainRow: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: 18))
            : AnyLayout(HStackLayout(spacing: 18))

        return layout {
            lightCamera
            lightSideColumn
                .frame(width: stacked ? nil : 380, height: stacked ? 420 : nil)
        }
    }

    /// The shared preview with camera-wait and failure notices on it. The side column is outside the
    /// preview, so nothing covers the patient.
    private var lightCamera: some View {
        camera
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if model.snapshot.cameraWaiting {
                        TherapyFeedbackPill(text: "session.cameraWait")
                    }

                    if let failure = model.failure {
                        Text(verbatim: failure)
                            .typography(.caption)
                            .foregroundStyle(TherapyPalette.warning)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let error = model.saveFailure {
                        saveError(error)
                    }
                }
                .padding(22)
            }
    }

    private var showsAnimation: Bool {
        guard let kind = model.snapshot.activity?.kind else {
            return false
        }

        return kind == .armRaise || kind == .elbowBend
    }

    /// The demonstration page also shows the towel animation; practice does not.
    private var showsDemonstration: Bool {
        showsAnimation || model.snapshot.activity?.kind == .foldTowel
    }

    private var lightSideColumn: some View {
        VStack(spacing: 18) {
            if showsAnimation {
                TherapyMediaPanel(title: "session.animation", padding: 18) {
                    demonstration
                        .background(TherapyPalette.exerciseBackdrop, in: RoundedRectangle(cornerRadius: 20))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .layoutPriority(1)
            }

            if let activity = model.snapshot.activity {
                TherapyRepetitionPanel(
                    title: "session.repetitionsTitle",
                    unit: "session.repetitionsUnit",
                    completed: model.snapshot.presentation?.count ?? 0,
                    total: activity.goal,
                    compact: true
                )
            }
        }
    }

    func lightString(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: model.sessionLanguage.resourceBundle,
            locale: model.sessionLocale
        )
    }
}

// MARK: - Stage pages

extension TherapySessionView {
    /// Instruction, demonstration, countdown, rest, feedback, pause and recovery, light.
    @ViewBuilder
    var lightStagePage: some View {
        VStack(spacing: 24) {
            lightStageHeader
            lightStageContent
            lightStageControls
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    /// Close pauses, as on the finger pages. A paused page has nothing left to pause.
    private var lightStageHeader: some View {
        TherapyPageHeader(
            title: lightTitle,
            leadingTitle: model.snapshot.paused ? nil : "session.pause",
            leadingSymbol: "pause.fill",
            leadingAction: model.snapshot.paused ? nil : { model.command(.pause) }
        )
    }

    @ViewBuilder
    private var lightStageContent: some View {
        if model.cameraDenied {
            recoveryPanel("therapy.session.cameraDenied")
        } else if model.snapshot.paused {
            lightPausePanel
        } else if model.isStarting {
            startupWaiting
        } else if !model.voiceReady {
            controlChoice
        } else if model.snapshot.stage == .preparing {
            preparingContent
        } else if model.snapshot.stage == .preparationWait {
            lightCountdown(
                "parity.getReady",
                seconds: model.snapshot.seconds,
                total: 5,
                running: model.snapshot.countdownRunning
            )
        } else if model.snapshot.stage == .activity,
            let seconds = model.snapshot.presentation?.countdownSeconds
        {
            lightCountdown(
                "stage.countdown",
                seconds: seconds,
                total: 3,
                running: model.snapshot.countdownRunning
            )
        } else if model.snapshot.stage == .instruction {
            lightGuidance(demonstrating: false)
        } else if model.snapshot.stage == .demonstration {
            lightGuidance(demonstrating: true)
        } else if model.snapshot.stage == .rest {
            lightRest
        } else if model.snapshot.stage == .feedback {
            lightFeedback
        } else {
            Spacer(minLength: 0)
        }
    }

    /// A title over a dial that fills the free height: the number is the page.
    private func lightCountdown(
        _ title: LocalizedStringKey,
        seconds: Int,
        total: Int,
        running: Bool,
        tint: Color = TherapyPalette.primary,
        track: Color = TherapyPalette.secondary,
        unit: LocalizedStringKey? = nil
    ) -> some View {
        VStack(spacing: 20) {
            Text(title)
                .typography(size: 52, weight: .bold, relativeTo: .largeTitle)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            TherapyCountdownDial(
                secondsLeft: seconds,
                total: total,
                running: running,
                tint: tint,
                track: track,
                unit: unit
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Guidance

    private func lightGuidance(demonstrating: Bool) -> some View {
        VStack(spacing: 16) {
            Text(demonstrating ? "session.example" : "session.guidanceHeading")
                .typography(size: 40, weight: .bold, relativeTo: .title)
                .accessibilityAddTraits(.isHeader)

            lightGuidanceBody(demonstrating: demonstrating)

            if voiceOver, let id = model.snapshot.guidanceID {
                TherapyButton(title: "session.readingComplete", pill: true) {
                    model.readingChanged(id, complete: true)
                }
                .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Text beside a framed animation, as on the finger demonstration page.
    @ViewBuilder
    private func lightGuidanceBody(demonstrating: Bool) -> some View {
        if demonstrating, showsDemonstration {
            HStack(spacing: 40) {
                lightGuidanceText(demonstrating: true)

                TherapyMediaPanel(padding: 14) {
                    demonstration
                        .background(TherapyPalette.exerciseBackdrop, in: RoundedRectangle(cornerRadius: 18))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            lightGuidanceText(demonstrating: demonstrating)
        }
    }

    @ViewBuilder
    private func lightGuidanceText(demonstrating: Bool) -> some View {
        if let id = model.snapshot.guidanceID {
            MeasuredInstructionText(
                phrase: guidancePhrase,
                instructionID: id,
                fontSize: demonstrating ? instructionSize / 2 : instructionSize * 2 / 3,
                reduceMotion: reduceMotion,
                voiceOver: voiceOver,
                textColor: .label,
                onReadingChanged: { id, complete in model.readingChanged(id, complete: complete) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Spacer(minLength: 0)
        }
    }

    // MARK: Rest and feedback

    private var lightRest: some View {
        lightCountdown(
            "rest.title",
            seconds: model.snapshot.seconds,
            total: Int(max(restTotal, Double(model.snapshot.seconds))),
            running: true,
            tint: TherapyPalette.restRing,
            track: TherapyPalette.restTrack,
            unit: "rest.seconds"
        )
    }

    private var lightFeedback: some View {
        VStack(spacing: 24) {
            TherapyCompletionMark()

            Text(LocalizedStringKey(model.snapshot.instruction))
                .typography(size: 44, weight: .bold, relativeTo: .largeTitle)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pause

    private var lightPausePanel: some View {
        ScrollView {
            TherapyCard(color: TherapyPalette.panel) {
                VStack(spacing: 16) {
                    Text("session.paused")
                        .typography(size: 44, weight: .bold, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)

                    Text("session.resumeHelp")
                        .typography(.body)
                        .multilineTextAlignment(.center)

                    if let failure = model.failure {
                        Text(verbatim: failure)
                            .typography(.caption)
                            .foregroundStyle(TherapyPalette.warning)
                    }

                    DisclosureGroup("session.assistance") {
                        VStack(spacing: 12) {
                            Button("session.repeat") { model.command(.repeatInstruction) }
                                .buttonStyle(SessionButtonStyle())
                            recoveryControls
                            Button("session.camera") { model.switchCamera() }
                                .buttonStyle(SessionButtonStyle())
                        }
                        .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Controls

    private var lightStageControls: some View {
        VStack(spacing: 12) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 16))

            layout {
                TherapyButton(
                    title: model.snapshot.paused ? "session.resume" : "session.pause",
                    disabled: model.snapshot.paused && !model.voiceReady,
                    pill: true
                ) {
                    model.command(model.snapshot.paused ? .resume : .pause)
                }

                TherapyButton(title: "therapy.session.stop", secondary: true, pill: true) {
                    model.command(.stop)
                }
            }
            .frame(maxWidth: 760)

            if let failure = model.failure, !model.snapshot.paused {
                Text(verbatim: failure)
                    .typography(.caption)
                    .foregroundStyle(TherapyPalette.warning)
            }

            if let error = model.saveFailure {
                saveError(error)
            }
        }
    }
}
