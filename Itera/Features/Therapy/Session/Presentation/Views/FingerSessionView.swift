//
//  FingerSessionView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerSessionView: View {
    @AppStorage(ExerciseMusicTrack.storageKey) private var musicTrack = ExerciseMusicTrack.defaultValue
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    /// Set when End was tapped on the live screen, so the pause dialog opens on its confirmation.
    @State private var endRequested = false

    var body: some View {
        Group {
            if let model = dependencies.session {
                session(model)
                    .environment(\.locale, model.sessionLanguage.locale)
                    .task { await model.start() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            model.foreground()
                        }
                        else if phase == .background {
                            model.background()
                        }
                    }
                    .onChange(of: model.hasFinished) { _, finished in
                        if finished {
                            router.replaceFullScreenCover(with: .sessionComplete)
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Exercise layout

    /// The shared live screen; stage pages, the countdown and the pause dialog lie over it.
    private func session(_ model: FingerSessionViewModel) -> some View {
        TherapyExerciseLiveLayout(
            heading: heading(model),
            cue: cue(model),
            demoTitle: "session.followMovement",
            repetitions: (model.activity.repetitions, model.routine.repetitions),
            sets: (model.activity.set, model.routine.sets),
            pauseTitle: "session.pauseAction",
            endTitle: "session.endAction",
            pauseDisabled: model.paused,
            demoWidthFraction: 0.76,
            onPause: { model.handleCommand(.pause) },
            onEnd: {
                endRequested = true
                model.handleCommand(.pause)
            }
        ) {
            camera(model)
        } demo: {
            example(model)
        } accessories: {
            accessories(model)
        }
        .accessibilityHidden(coversSession(model) || model.activity.phase == .countdown || model.paused)
        .overlay {
            phasePage(model)
                .ignoresSafeArea()
        }
        .overlay {
            if model.activity.phase == .countdown {
                TherapyCountdown(remaining: model.activity.remaining, total: 3,
                                 pause: model.pause, stop: { model.finish() })
                    .ignoresSafeArea()
            }
        }
        .overlay {
            if model.paused {
                FingerPauseDialog(model: model, confirmingEndInitially: endRequested) {
                    endRequested = false
                }
            }
        }
        .environment(\.colorScheme, .light)
        .statusBarHidden(true)
    }

    private func heading(_ model: FingerSessionViewModel) -> TherapyExerciseHeading {
        TherapyExerciseHeading(
            eyebrow: dependencies.dailyPlan.currentNumber.map { Text("plan.exerciseNumber \($0)") },
            title: Text(verbatim: model.exerciseTitle)
        )
    }

    /// Live feedback while tracking, otherwise the instruction; sequential movements add the finger.
    private func cue(_ model: FingerSessionViewModel) -> Text {
        let main = Text(LocalizedStringKey(liveCue(model) ?? model.instructionKey))

        guard model.activity.kind.isSequential, isTracking(model) else {
            return main
        }

        return main + Text(verbatim: "\n") + Text(LocalizedStringKey(model.fingerKey))
    }

    @ViewBuilder
    private func accessories(_ model: FingerSessionViewModel) -> some View {
        TherapyMusicMenu(
            selection: $musicTrack,
            options: ExerciseMusicTrack.allCases.map {
                TherapyMusicOption(id: $0.rawValue, title: LocalizedStringKey($0.titleKey))
            },
            size: 44
        )
        TherapyIconButton(title: "action.repeat", symbol: "speaker.wave.2.fill", size: 44, circle: true) {
            model.narrate()
        }
        TherapyIconButton(
            title: model.voiceEnabled ? "voice.on" : "voice.off",
            symbol: model.voiceEnabled ? "mic.fill" : "mic.slash",
            size: 44,
            circle: true
        ) {
            Task { await model.setVoice(!model.voiceEnabled) }
        }
    }

    private func isTracking(_ model: FingerSessionViewModel) -> Bool {
        [.baseline, .target, .range, .active].contains(model.activity.phase)
    }

    /// Shows the calibrated range, then lets the patient or caregiver start or measure again.
    private func rangeResult(_ model: FingerSessionViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("range.resultTitle").typography(.title)
                    .accessibilityAddTraits(.isHeader)
                TherapyRangeGauge(startLabel: "range.startEnd", endLabel: "range.farEnd")
                Text("range.target").typography(.headline)
                Text("range.repExplainer").typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
                Text("range.disclaimer").typography(.footnote)
                    .foregroundStyle(TherapyPalette.muted)
                VStack(alignment: .leading, spacing: 8) {
                    Text("range.autoStart").typography(.footnote)
                        .foregroundStyle(TherapyPalette.muted)
                    ProgressView(value: model.activity.rangeResultProgress)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 16) {
                    TherapyButton(title: "range.start", symbol: "play.fill", action: model.confirmRange)
                    TherapyButton(title: "range.remeasure", symbol: "arrow.clockwise", secondary: true, action: model.remeasureRange)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(TherapyPalette.cream)
    }


    // MARK: - Full-screen pages

    /// Demonstration, set completion and rest cover the whole session; the camera keeps
    /// running beneath, as the system design requires.
    @ViewBuilder
    private func phasePage(_ model: FingerSessionViewModel) -> some View {
        switch model.activity.phase {
        case .rangeResult:
            rangeResult(model)
        case .demonstration:
            demonstration(model)
        case .feedback:
            FingerSetSummaryPage(model: model)
        case .rest:
            if model.showsUpcomingPreview {
                FingerUpcomingPage(model: model)
            } else {
                FingerSetSummaryPage(model: model)
            }
        default:
            EmptyView()
        }
    }

    private func coversSession(_ model: FingerSessionViewModel) -> Bool {
        [.rangeResult, .demonstration, .feedback, .rest].contains(model.activity.phase)
    }

    // MARK: - Camera

    /// The live preview with the existing fingertip bubbles and their hold timer; recovery
    /// actions sit at the top, clear of the cue bubble at the bottom.
    private func camera(_ model: FingerSessionViewModel) -> some View {
        cameraPreview(model)
            .overlay(alignment: .top) {
                recovery(model)
                    .padding(22)
            }
    }

    /// Recovery guidance takes priority; otherwise the live hold/position feedback.
    private func liveCue(_ model: FingerSessionViewModel) -> String? {
        guard isTracking(model) else {
            return nil
        }

        return model.recoveryGuidanceKey ?? model.liveFeedbackKey
    }

    private func cameraPreview(_ model: FingerSessionViewModel) -> some View {
        ZStack(alignment: .bottomLeading) {
            TherapyPalette.cameraBackground
            HandCameraPreview(camera: model.camera, ready: model.previewReady)
                .accessibilityLabel("camera.preview")
            if let evidence = model.guideEvidence {
                FingerLandmarkOverlay(
                    evidence: evidence,
                    progress: model.activity.holdElapsed / model.activity.holdDuration,
                    exercise: model.activity.kind,
                    finger: model.activity.finger,
                    returning: model.activity.returning,
                    showsTimer: model.showsGuideTimer,
                    guiding: model.showsGuideIndicators,
                    completionID: model.activity.holdCompletionID,
                    onCompletionPresented: model.holdCompletionPresented
                )
            }
        }
    }

    @ViewBuilder
    private func recovery(_ model: FingerSessionViewModel) -> some View {
        if model.calibrationNeedsHelp {
            TherapyButton(title: "action.recalibrate", pill: true) {
                model.retryCalibration()
            }
            .frame(maxWidth: 320)
        } else if let key = model.errorKey {
            HStack(spacing: 12) {
                TherapyError(key: key)
                TherapyButton(title: "action.retry", pill: true) {
                    Task { await model.retryRecovery() }
                }
                .frame(width: 180)
            }
        }
    }

    private func example(_ model: FingerSessionViewModel) -> some View {
        FingerExampleView(
            exercise: model.activity.kind, phase: model.activity.phase,
            returning: model.activity.returning || model.activity.needsStart,
            finger: model.activity.finger, side: model.routine.side, paused: model.paused || model.waitingForCamera
        )
        .background(TherapyPalette.mediaBackground)
        .environment(\.therapyDemoCaptionHidden, true)
        .accessibilityLabel("session.example")
    }

    // MARK: - Demonstration

    private func demonstration(_ model: FingerSessionViewModel) -> some View {
        VStack(spacing: 0) {
            FingerSessionCloseHeader(model: model, title: LocalizedStringKey(model.activity.kind.title))

            HStack(spacing: 40) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(LocalizedStringKey(model.instructionKey))
                            .typography(size: 40, weight: .bold, relativeTo: .title)
                        Text("demo.followComfortably")
                            .typography(size: 22, weight: .regular, relativeTo: .body)
                            .foregroundStyle(TherapyPalette.muted)
                        sessionControls(model)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)

                TherapyMediaPanel(padding: 14) {
                    example(model)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .bottomLeading) {
                            TherapyMetric(title: "session.demoTime", value: model.demonstrationTimeText)
                                .frame(width: 160)
                                .padding(16)
                                .background(TherapyPalette.canvas, in: RoundedRectangle(cornerRadius: 20))
                                .padding(16)
                        }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 16)
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
    }

    private func sessionControls(_ model: FingerSessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                TherapyButton(title: "action.repeat", symbol: "speaker.wave.2.fill", secondary: true, pill: true, action: model.narrate)
                TherapyButton(title: model.voiceEnabled ? "voice.on" : "voice.off",
                              symbol: model.voiceEnabled ? "mic.fill" : "mic.slash", secondary: true, pill: true) {
                    Task { await model.setVoice(!model.voiceEnabled) }
                }
            }
            if let key = model.errorKey {
                TherapyError(key: key)
                TherapyButton(title: "action.retry", secondary: true, pill: true) {
                    Task {
                        await model.retryCamera()
                        await model.saveCheckpoint()
                    }
                }
            }
        }
    }
}
