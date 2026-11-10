//
//  FingerSessionView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMFingerSessionView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    /// Set when End was tapped on the live screen, so the pause dialog opens on its confirmation.
    @State private var endRequested = false
    @State private var videoBounds: CGRect?

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
        TMTherapyExerciseLiveLayout(
            heading: heading(model),
            cue: cue(model),
            cuePlacement: .video(videoBounds),
            demoTitle: "session.followMovement",
            repetitions: (model.activity.repetitions, model.routine.repetitions),
            sets: (model.activity.set, model.routine.sets),
            pauseTitle: "session.pauseAction",
            endTitle: "session.endAction",
            pauseDisabled: model.paused,
            calibrating: model.isCalibrating,
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
            EmptyView()
        }
        .accessibilityHidden(coversSession(model) || model.activity.phase == .countdown || model.paused)
        .overlay {
            phasePage(model)
                .ignoresSafeArea()
        }
        .overlay {
            if model.activity.phase == .countdown {
                TMPracticeCountdown(seconds: model.countdown, pause: model.pause, stop: { endRequested = true; model.pause() })
                    .ignoresSafeArea()
            }
        }
        .overlay {
            if model.paused {
                TMFingerPauseDialog(model: model, confirmingEndInitially: endRequested) {
                    endRequested = false
                }
            }
        }
        .environment(\.colorScheme, .light)
        .statusBarHidden(false)
    }

    private func heading(_ model: FingerSessionViewModel) -> TMTherapyExerciseHeading {
        TMTherapyExerciseHeading(
            eyebrow: dependencies.dailyPlan.currentNumber.map { Text("plan.exerciseNumber \($0)") },
            title: model.isCalibrating ? Text("stage.calibration") : Text(verbatim: model.exerciseTitle)
        )
    }

    /// Show one cue at a time, with the active finger inline when it is relevant.
    private func cue(_ model: FingerSessionViewModel) -> Text? {
        if let message = model.calibrationMessage, message != "calibration.try" {
            return Text(LocalizedStringKey(message))
        }

        if isTracking(model), !model.trackingReady {
            return Text(LocalizedStringKey(liveCue(model) ?? model.instructionKey))
        }

        let key = model.recoveryGuidanceKey ?? model.calibrationMessage ?? liveCue(model) ?? model.instructionKey
        let instruction = Text(LocalizedStringKey(key))

        guard model.activity.kind.isSequential, isTracking(model), model.recoveryGuidanceKey == nil else {
            return instruction
        }

        return instruction + Text(verbatim: " · ") + Text(LocalizedStringKey(model.fingerKey))
    }

    private func isTracking(_ model: FingerSessionViewModel) -> Bool {
        [.baseline, .target, .range, .active].contains(model.activity.phase)
    }

    // MARK: - Full-screen pages

    /// Set completion and rest cover the live layout without removing the camera.
    @ViewBuilder
    private func phasePage(_ model: FingerSessionViewModel) -> some View {
        switch model.activity.phase {
        case .feedback:
            TMFingerSetSummaryPage(model: model)
        case .rest:
            if let breath = model.restBreath {
                TMTherapyBreathingRest(
                    cue: LocalizedStringKey(breath.phase.key),
                    intensity: breath.intensity,
                    pause: model.pause,
                    stop: {
                        endRequested = true
                        model.pause()
                    },
                    skip: model.skipRest
                )
            } else if model.showsUpcomingPreview {
                TMFingerUpcomingPage(model: model)
            } else {
                TMFingerSetSummaryPage(model: model)
            }
        default:
            EmptyView()
        }
    }

    private func coversSession(_ model: FingerSessionViewModel) -> Bool {
        [.feedback, .rest].contains(model.activity.phase)
    }

    // MARK: - Camera

    /// The live preview with the existing fingertip bubbles and their hold timer; recovery
    /// actions sit at the top, clear of the cue bubble at the bottom.
    private func camera(_ model: FingerSessionViewModel) -> some View {
        cameraPreview(model)
            .overlay(alignment: .top) {
                VStack(spacing: 12) {
                    recovery(model)

                    if model.activity.phase == .rangeResult {
                        TMTherapyButton(
                            title: "range.remeasure",
                            symbol: "arrow.clockwise",
                            secondary: true,
                            pill: true,
                            action: model.remeasureRange
                        )
                        .frame(maxWidth: 320)
                    }
                }
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
            TherapyPalette.canvas
            TMHandCameraPreview(camera: model.camera, ready: model.previewReady) { bounds in
                videoBounds = bounds
            }
            .accessibilityLabel("camera.preview")
            if let evidence = model.guideEvidence {
                TMFingerLandmarkOverlay(
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
            TMTherapyButton(title: "action.recalibrate", pill: true) {
                model.retryCalibration()
            }
            .frame(maxWidth: 320)
        } else if let key = model.errorKey {
            HStack(spacing: 12) {
                TMTherapyError(key: key)
                TMTherapyButton(title: "action.retry", pill: true) {
                    Task { await model.retryRecovery() }
                }
                .frame(width: 180)
            }
        }
    }

    private func example(_ model: FingerSessionViewModel) -> some View {
        TMFingerExampleView(
            exercise: model.activity.kind,
            phase: model.calibrationMessage == "calibration.intro" ? .demonstration : model.activity.phase,
            returning: model.activity.returning || model.activity.needsStart,
            finger: model.activity.finger, side: model.routine.side, paused: model.paused || model.waitingForCamera
        )
        .background(TherapyPalette.mediaBackground)
        .environment(\.therapyDemoCaptionHidden, true)
        .accessibilityLabel("session.example")
    }
}
