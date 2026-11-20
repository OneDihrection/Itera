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
            demoTitle: LocalizedStringKey(model.demoTitleKey),
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
        .environment(\.colorScheme, .light)
        .statusBarHidden(false)
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

    private func heading(_ model: Service.Session) -> TMTherapyExerciseHeading {
        TMTherapyExerciseHeading(
            eyebrow: plan.currentNumber.map { Text("plan.exerciseNumber \($0)") },
            title: model.isCalibrating
                ? Text(LocalizedStringKey(model.usesOppositionScript
                    ? OppositionGuidance.prefix(for: model.routine.side) + "calibration.title"
                    : "stage.calibration"))
                : Text(verbatim: model.exerciseTitle)
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
