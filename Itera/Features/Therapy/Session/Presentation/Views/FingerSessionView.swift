//
//  FingerSessionView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerSessionView: View {
    @ScaledMetric(relativeTo: .body) private var guidanceHeight = 156.0
    @AppStorage(PracticePreferences.calmMode) private var calmMode = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let model = dependencies.session {
                session(model)
                    .task { await model.start() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            model.foreground()
                        }
                        else if phase == .background {
                            model.background()
                        }
                    }
                    .onChange(of: model.paused, initial: true) { _, paused in
                        if paused {
                            if router.presentedSheets.last?.route != .fingerPause {
                                router.presentSheet(.fingerPause)
                            }
                        } else if router.presentedSheets.last?.route == .fingerPause {
                            router.dismissSheet()
                        }
                    }
                    .onChange(of: model.needsReflection) { _, finished in
                        if finished {
                            if router.presentedSheets.last?.route == .fingerPause {
                                router.dismissSheet()
                            }
                            router.replaceFullScreenCover(with: .reflection)
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
    }

    private func session(_ model: FingerSessionViewModel) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                header(model)
                stage(model)
                    .overlay(alignment: .top) {
                        if model.waitingForCamera && !model.paused {
                            TherapyStatus(title: "camera.waiting", symbol: "video.slash")
                                .background(TherapyPalette.surface, in: Capsule())
                                .padding(16)
                        }
                    }
                ScrollView {
                    instruction(model)
                }
                .frame(height: min(guidanceHeight, geometry.size.height * 0.25))
            }
            .padding(18)
            .background(TherapyPalette.cream)
        }
        .accessibilityHidden(model.activity.phase == .countdown || model.paused)
        .overlay {
            if model.activity.phase == .countdown {
                TherapyCountdown(remaining: model.activity.remaining, total: 3,
                                 pause: model.pause, stop: { model.finish() })
                    .ignoresSafeArea()
            }
        }
        .statusBarHidden(true)
    }

    private func header(_ model: FingerSessionViewModel) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 24))

        return layout {
            sessionTitle(model)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 20) {
                TherapyMetric(title: "session.duration", value: model.timeText, compact: true)
                TherapyMetric(
                    title: "session.set",
                    value: "\(model.activity.set)/\(model.routine.sets)",
                    compact: true
                )
                TherapyMetric(
                    title: "session.repetitions",
                    value: "\(model.activity.repetitions)/\(model.routine.repetitions)",
                    compact: true
                )
                pauseButton(model)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(TherapyPalette.ink)
    }

    private func sessionTitle(_ model: FingerSessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(model.stageKey))
                .typography(.footnote)
                .foregroundStyle(TherapyPalette.primary)
            Text(LocalizedStringKey(model.activity.kind.title))
                .typography(.title)
                .lineLimit(2, reservesSpace: true)
        }
    }

    private func pauseButton(_ model: FingerSessionViewModel) -> some View {
        TherapyIconButton(title: "action.pause", symbol: "pause.fill", size: 92) {
            model.handleCommand(.pause)
        }
    }

    private func stage(_ model: FingerSessionViewModel) -> some View {
        // Overlays must not impose a new minimum size on the persistent camera viewport.
        camera(model)
            .accessibilityHidden([.demonstration, .feedback, .rest].contains(model.activity.phase))
            .overlay {
                if model.activity.phase == .demonstration {
                    demonstration(model)
                } else if model.activity.phase == .feedback {
                    VStack(spacing: 20) {
                        if !calmMode && !reduceMotion {
                            TherapyCelebration().id(model.celebrationID).frame(height: 250)
                        }
                        Text("session.setComplete").typography(.largeTitle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TherapyPalette.cream)
                } else if model.activity.phase == .rest {
                    rest(model)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rest(_ model: FingerSessionViewModel) -> some View {
        GeometryReader { geometry in
            ZStack {
                TherapyPalette.cream
                if !calmMode {
                    TherapyRestBackdrop(paused: model.paused || model.waitingForCamera)
                }
                ScrollView {
                    VStack(spacing: 20) {
                        Text("stage.rest").typography(.title)
                        ZStack {
                            TherapyProgressRing(progress: model.activity.remaining / Double(model.routine.restSeconds))
                            Text(verbatim: String(model.countdown)).typography(size: 100, weight: .bold)
                                .monospacedDigit().contentTransition(.numericText(countsDown: true))
                                .lineLimit(1).minimumScaleFactor(0.4)
                        }
                        .frame(width: min(250, geometry.size.height * 0.52), height: min(250, geometry.size.height * 0.52))
                        Text("rest.reassurance").typography(.body).foregroundStyle(TherapyPalette.muted)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
        }
    }

    private func camera(_ model: FingerSessionViewModel) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                TherapyPalette.cameraBackground
                HandCameraPreview(camera: model.camera, ready: model.previewReady)
                    .accessibilityLabel("camera.preview")
                if let evidence = model.guideEvidence {
                    FingerLandmarkOverlay(
                        evidence: evidence,
                        progress: model.activity.holdElapsed / model.activity.holdDuration,
                        remaining: model.activity.holdRemaining,
                        exercise: model.activity.kind,
                        finger: model.activity.finger,
                        returning: model.activity.returning,
                        showsTimer: model.showsGuideTimer,
                        guiding: model.showsGuideTimer,
                        completionID: model.activity.holdCompletionID,
                        onCompletionPresented: model.holdCompletionPresented
                    )
                }
                HStack(alignment: .top) {
                    Text(LocalizedStringKey(model.routine.side.title)).typography(.headline)
                        .padding(14).background(TherapyPalette.surface, in: Capsule())
                    Spacer(minLength: 16)
                    if [.baseline, .target, .active].contains(model.activity.phase) {
                        example(model)
                            .frame(
                                width: min(250, geometry.size.width * 0.3),
                                height: min(265, geometry.size.height * 0.8)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                }
                .padding(20)
            }
        }
    }

    private func example(_ model: FingerSessionViewModel) -> some View {
        FingerDemonstrationView(
            exercise: model.activity.kind, phase: model.activity.phase,
            returning: model.activity.returning || model.activity.needsStart,
            finger: model.activity.finger, side: model.routine.side, paused: model.paused || model.waitingForCamera
        )
        .background(TherapyPalette.mediaBackground)
        .accessibilityLabel("session.example")
    }

    private func demonstration(_ model: FingerSessionViewModel) -> some View {
        HStack(spacing: 30) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(LocalizedStringKey(model.instructionKey))
                        .typography(size: 42, weight: .bold, relativeTo: .title)
                    Text("demo.followComfortably").typography(.body)
                        .foregroundStyle(TherapyPalette.muted)
                    sessionControls(model)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity)
            example(model).frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) {
                    TherapyMetric(title: "session.demoTime", value: model.demonstrationTimeText)
                        .frame(width: 160)
                        .padding(18)
                        .background(TherapyPalette.surface, in: RoundedRectangle(cornerRadius: 22))
                        .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .padding(28)
        .background(TherapyPalette.cream)
    }

    private func sessionControls(_ model: FingerSessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                TherapyButton(title: "action.repeat", symbol: "speaker.wave.2.fill", secondary: true, action: model.narrate)
                TherapyButton(title: model.voiceEnabled ? "voice.on" : "voice.off",
                              symbol: model.voiceEnabled ? "mic.fill" : "mic.slash", secondary: true) {
                    Task { await model.setVoice(!model.voiceEnabled) }
                }
            }
            if let key = model.errorKey {
                TherapyError(key: key)
                TherapyButton(title: "action.retry", secondary: true) {
                    Task {
                        await model.retryCamera()
                        await model.saveCheckpoint()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func instruction(_ model: FingerSessionViewModel) -> some View {
        if model.activity.phase != .demonstration {
            VStack(spacing: 14) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(model.instructionKey))
                            .typography(size: 36, weight: .bold, relativeTo: .title)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.activity.phase == .target || model.activity.phase == .active {
                            Text("guide.holdDuration \(Int(model.activity.holdDuration))")
                                .typography(.callout)
                        }
                        HStack(spacing: 14) {
                            if model.activity.kind.isSequential && [.baseline, .target, .active].contains(model.activity.phase) {
                                Text(LocalizedStringKey(model.fingerKey)).typography(.headline)
                            }
                            if [.baseline, .target, .active].contains(model.activity.phase) && model.trackingReady {
                                Text(LocalizedStringKey(model.liveFeedbackKey)).typography(.callout)
                                    .foregroundStyle(TherapyPalette.primary)
                            }
                        }
                    }
                    Spacer(minLength: 12)
                    Button(action: model.narrate) {
                        Image(systemName: "speaker.wave.2.fill").typography(.title2)
                            .frame(width: 68, height: 68)
                            .background(TherapyPalette.surface, in: Circle())
                    }
                    .buttonStyle(TherapySoundButtonStyle()).accessibilityLabel("action.repeat")
                    Button {
                        Task { await model.setVoice(!model.voiceEnabled) }
                    } label: {
                        Image(systemName: model.voiceEnabled ? "mic.fill" : "mic.slash")
                            .typography(.title2).frame(width: 68, height: 68)
                            .background(TherapyPalette.surface, in: Circle())
                    }
                    .buttonStyle(TherapySoundButtonStyle())
                    .accessibilityLabel(model.voiceEnabled ? "voice.on" : "voice.off")
                }
                if [.baseline, .target, .active].contains(model.activity.phase) {
                    ProgressView(value: model.activity.holdElapsed / model.activity.holdDuration).tint(TherapyPalette.primary)
                        .accessibilityLabel("session.holdProgress")
                }
                if let key = model.errorKey {
                    HStack {
                        TherapyError(key: key)
                        TherapyButton(title: "action.retry", secondary: true) {
                            Task { await model.retryCamera() }
                        }.frame(width: 160)
                    }
                }
            }
            .foregroundStyle(TherapyPalette.ink)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(TherapyPalette.secondary, in: RoundedRectangle(cornerRadius: 28))
        }
    }

}
