//
//  FingerSessionView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMFingerSessionView<Service: FingerSessionServiceProtocol>: View {
    private let fingerSessionService: Service
    private let plan: any DailyPlanSessionReporting
    private let router: any SessionRouterProtocol

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set when End was tapped on the live screen, so the pause dialog opens on its confirmation.
    @State private var endRequested = false
    @State private var videoBounds: CGRect?

    init(
        fingerSessionService: Service,
        plan: any DailyPlanSessionReporting,
        router: any SessionRouterProtocol
    ) {
        self.fingerSessionService = fingerSessionService
        self.plan = plan
        self.router = router
    }

    var body: some View {
        Group {
            if let model = fingerSessionService.session {
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
                            plan.markOppositionRest(model.usesOppositionScript ? model.routine.side : nil)
                            router.showFingerSessionComplete()
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Exercise layout

    /// The shared live screen; stage pages, the countdown and the pause dialog lie over it.
    private func session(_ model: Service.Session) -> some View {
        TMTherapyExerciseLiveLayout(
            heading: heading(model),
            cuePlacement: .video(videoBounds),
            repetitions: (model.activity.repetitions, model.routine.repetitions),
            sets: (model.activity.set, model.routine.sets),
            pauseTitle: "session.pauseAction",
            endTitle: "session.endAction",
            pauseDisabled: model.paused,
            calibrating: model.isCalibrating,
            demoWidthFraction: 0.94,
            demoRevision: model.demoRevision,
            demoAnnouncement: model.demoAnnouncement,
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
                TMPracticeCountdown(
                    seconds: model.countdown,
                    title: model.usesOppositionScript && model.activity.set > 1
                        ? LocalizedStringKey(OppositionGuidance.prefix(for: model.routine.side) + "countdown.next")
                        : "calibration.countdown",
                    pause: model.pause,
                    stop: {
                        endRequested = true
                        model.pause()
                    }
                )
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
        .overlay(alignment: .topTrailing) {
            debugFinishButton(model)
        }
        .overlay {
            debugSkipRestButton(model)
        }
        .overlay {
            loadingOverlay(model)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: model.isPreparing || model.isFinishing
        )
        .environment(\.colorScheme, .light)
        .statusBarHidden(false)
    }

    /// Covers starting and ending, which do synchronous main-actor work.
    @ViewBuilder
    private func loadingOverlay(_ model: Service.Session) -> some View {
        if model.isPreparing {
            TMLoadingOverlay(message: "loading.preparingSession")
        } else if model.isFinishing {
            TMLoadingOverlay(message: "loading.finishingSession")
        }
    }

    /// Debug builds only. Over the header's trailing corner, above stage pages and the pause
    /// dialog, rather than in `accessories`, which would move the centred heading.
    @ViewBuilder
    private func debugFinishButton(_ model: Service.Session) -> some View {
        #if DEBUG
        if !model.hasFinished {
            TMDebugActionButton(title: "debug.finishExercise", symbol: "forward.end.fill") {
                model.finishExerciseForDebug()
            }
            .padding(.top, 12)
            .padding(.trailing, 20)
        }
        #endif
    }

    /// Debug builds only: on the breathing rest pages, which show no Skip of their own, ends the
    /// rest through the session's existing `skipRest()`. The set and "next up" pages already offer
    /// Skip during the rest.
    @ViewBuilder
    private func debugSkipRestButton(_ model: Service.Session) -> some View {
        #if DEBUG
        if model.activity.phase == .rest,
           model.scriptedRest != nil || model.restBreath != nil,
           !model.paused,
           !model.hasFinished {
            TMDebugSkipRestButton(action: model.skipRest)
        }
        #endif
    }

    private func heading(_ model: Service.Session) -> TMTherapyExerciseHeading {
        guard !model.isCalibrating else {
            return .calibration
        }

        return TMTherapyExerciseHeading(
            eyebrow: plan.currentNumber.map { Text("plan.exerciseNumber \($0)") },
            title: Text(verbatim: model.exerciseTitle)
        )
    }

    // MARK: - Full-screen pages

    /// Set completion and rest cover the live layout without removing the camera.
    @ViewBuilder
    private func phasePage(_ model: Service.Session) -> some View {
        switch model.activity.phase {
        case .feedback:
            TMFingerSetSummaryPage(model: model, exerciseNumber: plan.currentNumber)
        case .rest:
            if let rest = model.scriptedRest {
                TMTherapyBreathingRest(
                    cue: LocalizedStringKey(rest.cueKey(prefix: OppositionGuidance.prefix(for: model.routine.side))),
                    intensity: rest.intensity,
                    paused: model.paused,
                    pause: model.pause,
                    stop: {
                        endRequested = true
                        model.pause()
                    },
                    skip: model.skipRest
                )
            } else if let breath = model.restBreath {
                TMTherapyBreathingRest(
                    cue: LocalizedStringKey(breath.phase.key),
                    intensity: breath.intensity,
                    paused: model.paused,
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
                TMFingerSetSummaryPage(model: model, exerciseNumber: plan.currentNumber)
            }
        default:
            EmptyView()
        }
    }

    private func coversSession(_ model: Service.Session) -> Bool {
        [.feedback, .rest].contains(model.activity.phase)
    }

    // MARK: - Camera

    /// The live preview with the existing fingertip bubbles and their hold timer; recovery
    /// actions sit at the top, clear of the cue bubble at the bottom.
    private func camera(_ model: Service.Session) -> some View {
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

    /// Whether the hand is in position, for the chip over the camera; nil hides it.
    /// `trackingReady` is already settled by `FingerTrackingRecovery`, so it does not flicker
    /// on a dropped frame.
    private func trackingPositioned(_ model: Service.Session) -> Bool? {
        guard !model.isPreparing,
              !model.isFinishing,
              !model.paused,
              !model.waitingForCamera,
              model.errorKey == nil else {
            return nil
        }

        switch model.activity.phase {
        case .countdown, .feedback, .rest, .finished:
            return nil
        default:
            return model.trackingReady
        }
    }

    /// Whether the chip is muted: tracking is shown but the hand is not being acted on, while
    /// narration or the demonstration holds the exercise back.
    private func trackingMuted(_ model: Service.Session) -> Bool {
        model.calibrationMessage == "calibration.intro"
            || !model.activity.actsOnMovement
    }

    private func cameraPreview(_ model: Service.Session) -> some View {
        ZStack(alignment: .bottomLeading) {
            TherapyPalette.canvas
            TMHandCameraPreview(cameraService: model.cameraService, ready: model.previewReady) { bounds in
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
                    openness: model.activity.gripOpenness,
                    completionID: model.activity.holdCompletionID,
                    onCompletionPresented: model.holdCompletionPresented
                )
                // The targets are drawn quietly until the countdown ends.
                .opacity(model.activity.phase == .countdown ? 0.6 : 1)
                .animation(.easeOut(duration: 0.35), value: model.activity.phase == .countdown)
            }
        }
        .trackingStatusChip(
            trackingPositioned(model),
            muted: trackingMuted(model),
            videoBounds: videoBounds
        )
    }

    @ViewBuilder
    private func recovery(_ model: Service.Session) -> some View {
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

    private func example(_ model: Service.Session) -> some View {
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
